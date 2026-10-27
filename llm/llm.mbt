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
/// `reasoning_content` is a provider extension the typed response drops.
fn reasoning_of(raw : Json) -> String? {
  match raw {
    {
      "choices": [{ "message": { "reasoning_content": String(s), .. }, .. }, ..],
      ..
    } => Some(s)
    _ => None
  }
}

///|
/// Meta Model API reports usage but no price, so `cost_usd` is computed
/// from the model's list rate. Rates are dollars per million tokens;
/// reasoning tokens are billed as output and are included in
/// `completion_tokens`.
fn rate_of(model : String) -> (Double, Double)? {
  match model {
    "muse-wonder-1.0" => Some((4.0, 20.0))
    "muse-spark-1.3" | "muse-spark-1.2" | "muse-spark-1.1" => Some((1.25, 4.25))
    "muse-spark-1.3-contributor" | "muse-spark-1.2-contributor" =>
      Some((0.10, 0.20))
    _ => None
  }
}

///|
fn usage_of(model : String, raw : Json) -> Usage {
  guard raw is { "usage": Object(u), .. } else { return Usage::zero() }
  let int = (j : Json?) => if j is Some(Number(n, ..)) { n.to_int() } else { 0 }
  let input = int(u.get("prompt_tokens"))
  let output = int(u.get("completion_tokens"))
  {
    input,
    output,
    reasoning: match u.get("completion_tokens_details") {
      Some({ "reasoning_tokens": Number(n, ..), .. }) => n.to_int()
      _ => 0
    },
    cost_usd: match rate_of(model) {
      Some((input_rate, output_rate)) =>
        input.to_double() * input_rate / 1_000_000.0 +
        output.to_double() * output_rate / 1_000_000.0
      None => 0.0
    },
  }
}
