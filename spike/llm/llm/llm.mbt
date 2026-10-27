///|
/// One model call, fully specified. Everything that can change the output is
/// a field here, so `key` can address a cached reply.
pub(all) struct Call {
  model : String
  /// System prompt blocks, in order. Kept separate so a provider with prompt
  /// caching can put a breakpoint after the shared prefix.
  system : Array[String]
  user : String
  max_tokens : Int32
  temperature : Double?
  reasoning_effort : String?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub fn Call::new(
  model~ : String,
  system~ : Array[String],
  user~ : String,
  max_tokens~ : Int32,
  temperature? : Double,
  reasoning_effort? : String,
) -> Call {
  { model, system, user, max_tokens, temperature, reasoning_effort, }
}

///|
pub fn Call::with_user(self : Call, user : String) -> Call {
  { ..self, user, }
}

///|
/// Hex sha256 of the call's json. Field order is declaration order, so the
/// json is canonical as long as `Call` does not change shape.
pub fn Call::key(self : Call) -> String {
  hex(@crypto.sha256(@utf8.encode(self.to_json().stringify())))
}

///|
fn hex(bytes : FixedArray[Byte]) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder()
  for b in bytes {
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
  usage : Usage
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A way to run a call. Wrappers (`limited`, `@cache.cached`) return another
/// `Backend`, so they compose.
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
  {
    name: self.name,
    run: async fn(c) {
      sem.acquire()
      defer sem.release()
      self.call(c)
    },
  }
}

///|
/// An OpenAI-compatible chat completions endpoint, e.g. hyper.
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
    // The default retries POSTs, which can bill a call twice.
    retry=@runtime.RetryPolicy::conservative(),
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
      usage: usage_of(res.raw),
    }
  })
}

///|
/// `reasoning_content` is a DeepSeek extension the typed response drops.
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
/// Usage including hyper's `cost.usd` extension.
fn usage_of(raw : Json) -> Usage {
  guard raw is { "usage": Object(u), .. } else { return Usage::zero() }
  let int = (j : Json?) => if j is Some(Number(n, ..)) { n.to_int() } else { 0 }
  {
    input: int(u.get("prompt_tokens")),
    output: int(u.get("completion_tokens")),
    reasoning: match u.get("completion_tokens_details") {
      Some({ "reasoning_tokens": Number(n, ..), .. }) => n.to_int()
      _ => 0
    },
    cost_usd: match u.get("cost") {
      Some({ "usd": Number(n, ..), .. }) => n
      _ => 0
    },
  }
}
