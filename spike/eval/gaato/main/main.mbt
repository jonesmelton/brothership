///|
/// Two system blocks: a long shared preamble cached for 1h, then a per-item
/// block. Structured output via `output_config.format`.
fn build_params() -> @gen.CreateMessageParams {
  let cached = @gen.RequestTextBlockCacheControl::Ephemeral(
    @gen.CacheControlEphemeral::new(type_="ephemeral", ttl=Value1h),
  )
  let system = @gen.CreateMessageParamsSystem::RequestTextBlockArray([
    @gen.RequestTextBlock::new(
      type_="text",
      text="# setting\nYou narrate a sentient starship crew.",
      cache_control=cached,
    ),
    @gen.RequestTextBlock::new(type_="text", text="# item\nShip: Song Jiang."),
  ])
  let schema : Json = {
    "type": "object",
    "properties": { "line": { "type": "string" } },
    "required": ["line"],
    "additionalProperties": false,
  }
  @gen.CreateMessageParams::new(
    model="claude-haiku-4-5",
    max_tokens=256,
    system~,
    messages=[
      @gen.InputMessage::new(
        role=User,
        content=@gen.InputMessageContent::Text("Give one line of dialogue."),
      ),
    ],
    output_config=@gen.OutputConfig::new(
      format=@gen.JsonOutputFormat::new(schema~),
    ),
  )
}

///|
async fn main {
  let params = build_params()
  println(Json(params).stringify(indent=2))
  // OpenAI-compatible local server: construction only, no request sent.
  let _local = @openai.OpenAI::new(
    api_key="unused",
    @http_async.AsyncTransport::new(timeout_ms=600_000),
    @http_async.AsyncClock::new(),
    base_url="http://127.0.0.1:8080/v1",
  )
  guard @env.get_env_var("ANTHROPIC_API_KEY") is Some(api_key) else {
    println("ANTHROPIC_API_KEY unset; not sending")
  }
  let client = @anthropic.Anthropic::new(
    api_key~,
    @http_async.AsyncTransport::new(
      timeout_ms=600_000,
      connect_timeout_ms=5_000,
      max_body_bytes=64 * 1024 * 1024,
    ),
    @http_async.AsyncClock::new(),
    timer=@http_async.ClockTimer::new(),
    total_timeout_ms=900_000,
    retry=@runtime.RetryPolicy::conservative(),
  )
  let message = client.create_message_params(params)
  println(Json(message.content).stringify())
  println(Json(message.usage).stringify())
}
