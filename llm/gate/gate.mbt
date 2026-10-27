///|
/// A policy-following classifier for model text shown to players: the policy
/// is the system prompt, and the text to judge is the only user message.
pub struct Gate {
  model : String
  policy : String
}

///|
pub fn Gate::new(model~ : String, policy~ : String) -> Gate {
  { model, policy, }
}

///|
pub(all) enum Verdict {
  Clean
  /// The shortest quote that decided it, or empty if the model gave none.
  Violation(String)
} derive(Eq, Debug)

///|
pub(all) suberror Unreadable {
  Unreadable(String)
} derive(Debug)

///|
pub impl Show for Unreadable with fn output(self, logger) {
  let Unreadable(why) = self
  logger.write_string(why)
}

///|
/// The id is a hash of the text, so the text cannot contain its own closing
/// tag, and the same text makes the same call for the reply cache.
pub fn wrap(text : String) -> String {
  let id = @llm.sha256_hex(text)[0:12].to_owned()
  "<message id=\{id}>\n\{text}\n</message id=\{id}>"
}

///|
pub fn Gate::call(self : Gate, text : String) -> @llm.Call {
  @llm.Call::new(
    model=self.model,
    system=[self.policy],
    user=wrap(text),
    max_tokens=4000,
    reasoning_effort="medium",
  )
}

///|
pub async fn Gate::check(
  self : Gate,
  backend : @llm.Backend,
  text : String,
) -> Verdict {
  decode(backend.call(self.call(text)).text)
}

///|
/// Reads the JSON object from the reply's first `{` to its last `}`.
pub fn decode(reply : String) -> Verdict raise Unreadable {
  let unreadable = Unreadable(
    "no verdict in the reply: \{reply.view(end_offset=reply.length().min(200))}",
  )
  guard reply.find("{") is Some(start) &&
    reply.rev_find("}") is Some(end) &&
    end > start else {
    raise unreadable
  }
  let object = @json.parse(reply[start:end + 1]) catch { _ => raise unreadable }
  match object {
    { "violation": Number(0, ..), .. } => Clean
    { "violation": Number(1, ..), "evidence": String(e), .. } => Violation(e)
    { "violation": Number(1, ..), .. } => Violation("")
    _ => raise unreadable
  }
}
