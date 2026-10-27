///|
/// One model call, fully specified. Everything that can change the output is
/// a field here, so `key` can address a cached reply.
pub(all) struct Call {
  /// `provider:model`, e.g. `meta:muse-wonder-1.0`. `route` strips
  /// the provider before the call reaches it.
  model : String
  /// System prompt blocks, in order. Kept separate so a provider with prompt
  /// caching can put a breakpoint after the shared prefix.
  system : Array[String]
  user : String
  max_tokens : Int32
  temperature : Double?
  reasoning_effort : String?
  /// Which of several drafts of the same prompt this is. Never sent; it only
  /// gives each draft its own key.
  sample : Int32
} derive(Eq, Debug, ToJson, FromJson)

///|
pub fn Call::new(
  model~ : String,
  system~ : Array[String],
  user~ : String,
  max_tokens~ : Int32,
  temperature? : Double,
  reasoning_effort? : String,
  sample~ : Int32 = 1,
) -> Call {
  { model, system, user, max_tokens, temperature, reasoning_effort, sample, }
}

///|
pub fn Call::with_user(self : Call, user : String) -> Call {
  { ..self, user, }
}

///|
/// Hex sha256 of the call's json. Field order is declaration order, so the
/// json is canonical as long as `Call` does not change shape.
pub fn Call::key(self : Call) -> String {
  sha256_hex(self.to_json().stringify())
}

///|
pub fn sha256_hex(text : String) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder()
  for b in @crypto.sha256(@utf8.encode(text)) {
    buf.write_char(digits.get_char(b.to_int() >> 4).unwrap())
    buf.write_char(digits.get_char(b.to_int() & 15).unwrap())
  }
  buf.to_string()
}

///|
pub(all) struct Usage {
  input : Int32
  output : Int32
  reasoning : Int32
  cost_usd : Double
} derive(Eq, Debug, ToJson, FromJson)

///|
pub fn Usage::zero() -> Usage {
  { input: 0, output: 0, reasoning: 0, cost_usd: 0, }
}

///|
pub(all) struct Reply {
  model : String
  text : String
  reasoning : String?
  /// The provider's finish reason as it sent it: `stop`, `length`, ...
  finish : String?
  usage : Usage
  /// The provider's response body, kept for the generation record.
  raw : Json
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) suberror LlmError {
  UnknownProvider(String)
  /// An empty reply, or one cut off by the token limit. Thinking models can
  /// spend the whole budget thinking and return nothing.
  Incomplete(String)
} derive(Debug)

///|
pub impl Show for LlmError with fn output(self, logger) {
  match self {
    UnknownProvider(p) => logger.write_string("unknown provider \{p}")
    Incomplete(why) => logger.write_string("incomplete reply: \{why}")
  }
}

///|
/// A way to run a call. Wrappers (`limited`, `retrying`, `route`,
/// `@cache.cached`) return another `Backend`, so they compose.
pub struct Backend {
  name : String
  run : async (Call) -> Reply
}

///|
pub fn Backend::new(name : String, run : async (Call) -> Reply) -> Backend {
  { name, run, }
}

///|
pub async fn Backend::call(self : Backend, c : Call) -> Reply {
  (self.run)(c)
}

///|
/// At most `n` calls through the result run at once.
pub fn Backend::limited(self : Backend, n : Int32) -> Backend {
  let sem = @semaphore.Semaphore(n)
  Backend::new(self.name, async fn(c) {
    sem.acquire()
    defer sem.release()
    self.call(c)
  })
}

///|
/// Sends `provider:model` calls to `providers[provider]` with the bare model.
pub fn Backend::route(providers : Map[String, Backend]) -> Backend {
  Backend::new("route", async fn(c) {
    guard c.model.split(":").to_array() is [provider, .. rest] &&
      rest.length() > 0 else {
      raise UnknownProvider(c.model)
    }
    guard providers.get(provider.to_owned()) is Some(b) else {
      raise UnknownProvider(provider.to_owned())
    }
    b.call({ ..c, model: rest.map(s => s.to_owned()).join(":"), })
  })
}

///|
/// Reruns a call after an empty or truncated reply, or a transient provider
/// error, with exponential backoff. Other errors pass straight through.
pub fn Backend::retrying(
  self : Backend,
  max_retry~ : Int32 = 3,
  delay_ms~ : Int32 = 2000,
) -> Backend {
  Backend::new(self.name, async fn(c) {
    @async.retry(
      ExponentialDelay(initial=delay_ms, factor=2, maximum=60_000),
      max_retry~,
      fatal_error=e => !transient(e),
      () => {
        let r = self.call(c)
        if r.text.trim() == "" {
          raise Incomplete("empty")
        }
        if r.finish is Some("length") {
          raise Incomplete("hit max_tokens \{c.max_tokens}")
        }
        r
      },
    )
  })
}

///|
fn transient(e : Error) -> Bool {
  match e {
    Incomplete(_) => true
    @runtime.Transport(_) | @runtime.RateLimited(..) => true
    @runtime.Status(status~, ..) =>
      status == 408 || status == 409 || status == 429 || status >= 500
    _ => false
  }
}

///|
/// An OpenAI-compatible chat completions endpoint, e.g. Meta Model API.
/// System blocks are joined into one system message.
pub fn Backend::openai_compatible(
  base_url~ : String,
  api_key~ : String,
) -> Backend {
  let client = @openai.OpenAI::new(
    api_key~,
    // The transport default of 30 s kills long generations.
    @http_async.AsyncTransport::new(timeout_ms=600_000),
    @http_async.AsyncClock::new(),
    base_url~,
    // No retries inside the client: the default retries POSTs, which can bill
    // a call twice, and `retrying` handles the cases worth retrying.
    retry=@runtime.RetryPolicy::none(),
    timer=@http_async.ClockTimer::new(),
    total_timeout_ms=900_000,
  )
  Backend::new(base_url, async fn(c) {
    let req = @openai.ChatRequest::new(
      model=c.model,
      messages=[
        @openai.ChatMessage::system(c.system.join("\n\n")),
        @openai.ChatMessage::user(c.user),
      ],
      max_tokens=c.max_tokens,
      temperature?=c.temperature,
      reasoning_effort?=c.reasoning_effort,
    )
    let res = client.chat_completion(req)
    {
      model: res.model,
      text: res.text,
      reasoning: reasoning_of(res.raw),
      finish: finish_of(res.raw),
      usage: usage_of(res.model, res.raw),
      raw: res.raw,
    }
  })
}

///|
fn finish_of(raw : Json) -> String? {
  match raw {
    { "choices": [{ "finish_reason": String(s), .. }, ..], .. } => Some(s)
    _ => None
  }
}

///|
/// Reasoning is a provider extension the typed response drops: Meta sends
/// `reasoning_content`, Groq sends `reasoning`.
fn reasoning_of(raw : Json) -> String? {
  match raw {
    {
      "choices": [{ "message": { "reasoning_content": String(s), .. }, .. }, ..],
      ..
    }
    | { "choices": [{ "message": { "reasoning": String(s), .. }, .. }, ..], .. } =>
      Some(s)
    _ => None
  }
}

///|
/// (cached input, input, output) list rates in dollars per million tokens.
/// Meta Model API reports token counts but no price, so `cost_usd` is
/// computed from these. Reasoning tokens are billed as output and are
/// included in `completion_tokens`.
priv struct Rates {
  cached : Double
  input : Double
  output : Double
}

///|
fn rate_of(model : String) -> Rates? {
  match model {
    "muse-wonder-1.0" => Some({ cached: 0.20, input: 4.0, output: 20.0, })
    "muse-spark-1.3" | "muse-spark-1.2" | "muse-spark-1.1" =>
      Some({ cached: 0.15, input: 1.25, output: 4.25, })
    "muse-spark-1.3-contributor" | "muse-spark-1.2-contributor" =>
      Some({ cached: 0.002, input: 0.10, output: 0.20, })
    _ => None
  }
}

///|
/// Total and cached split of the input tokens in one response's `usage`.
/// Recording both is the only per-call billing record: Meta Model API has
/// no usage or billing endpoint, only the dashboard at dev.meta.ai/usage.
fn prompt_tokens(raw : Json) -> (Int32, Int32) {
  match raw {
    { "usage": Object(u), .. } => {
      let total = match u.get("prompt_tokens") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let cached = match u.get("prompt_tokens_details") {
        Some({ "cached_tokens": Number(n, ..), .. }) => n.to_int()
        _ => 0
      }
      (total, cached)
    }
    _ => (0, 0)
  }
}

///|
/// Cost in dollars of one response, or `None` for a model with no rate.
fn cost_of(model : String, raw : Json) -> Double? {
  guard rate_of(model) is Some(rates) else { return None }
  guard raw is { "usage": Object(u), .. } else { return None }
  let int = (j : Json?) => if j is Some(Number(n, ..)) { n.to_int() } else { 0 }
  let (prompt_total, cached) = prompt_tokens(raw)
  let uncached = prompt_total - cached
  let cost = cached.to_double() * rates.cached / 1_000_000.0 +
    uncached.to_double() * rates.input / 1_000_000.0 +
    int(u.get("completion_tokens")).to_double() * rates.output / 1_000_000.0
  Some(cost)
}

///|
fn usage_of(model : String, raw : Json) -> Usage {
  guard raw is { "usage": Object(u), .. } else { return Usage::zero() }
  let int = (j : Json?) => if j is Some(Number(n, ..)) { n.to_int() } else { 0 }
  {
    input: int(u.get("prompt_tokens")),
    output: int(u.get("completion_tokens")),
    reasoning: match u.get("completion_tokens_details") {
      Some({ "reasoning_tokens": Number(n, ..), .. }) => n.to_int()
      _ => 0
    },
    cost_usd: cost_of(model, raw).unwrap_or(0.0),
  }
}
