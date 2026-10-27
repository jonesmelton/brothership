///|
/// Captures the request body and answers with a canned Messages reply, so the
/// serialized request can be inspected without a key.
struct Capture {
  mut last : String
}

///|
impl @provider_utils.HttpTransport for Capture with fn fetch(self, req) {
  self.last = req.body_text()
  println("POST \{req.url}")
  println(self.last)
  @provider_utils.HttpResponse::text(
    status_code=200,
    headers={ "content-type": "application/json" },
    body=(
      #|{"id":"msg_x","type":"message","role":"assistant","model":"claude-haiku-4-5",
      #|"content":[{"type":"text","text":"canned"}],"stop_reason":"end_turn",
      #|"usage":{"input_tokens":12,"output_tokens":3,"cache_read_input_tokens":0,
      #|"cache_creation_input_tokens":9}}
    ),
  )
}

///|
impl @provider_utils.HttpTransport for Capture with fn fetch_stream(_self, _req) {
  fail("streaming not mocked")
}

///|
fn cached() -> Map[String, Json] {
  { "anthropic": { "cacheControl": { "type": "ephemeral" } } }
}

///|
async fn main {
  let live = @env.get_env_var("ANTHROPIC_API_KEY") is Some(_)
  let model = if live {
    @anthropic.anthropic("claude-haiku-4-5")
  } else {
    @anthropic.anthropic(
      "claude-haiku-4-5",
      api_key="sk-test",
      http_transport=Capture::{ last: "" },
    )
  }
  let messages = [
    // three system sources; the breakpoint sits on the last stable one
    @provider_utils.ModelMessage::system("# ship\nYou are the Jade Unicorn."),
    @provider_utils.ModelMessage::system(
      "# crew\n108 stars.",
      provider_options=cached(),
    ),
    @provider_utils.ModelMessage::system("# stage\nturn 3"),
    @provider_utils.ModelMessage::user("Report."),
  ]
  let result = @ai.generate_text(
    model,
    messages~,
    allow_system_in_messages=true,
    max_output_tokens=256,
    retry_policy=@provider.RetryPolicy::standard(),
  )
  println("text=\{result.text()}")
  println("usage=\{@debug.to_string(result.usage)}")
}
