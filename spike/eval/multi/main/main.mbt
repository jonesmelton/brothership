fn main {
  let ctx : @llm.LlmContext = {
    system: Some("sys"),
    messages: [UserMsg(content=[UserText("hi")])],
    tools: [],
    params: @llm.LlmParams::default(),
  }
  let d = @anthropic.AnthropicDialect::make(model="claude-haiku-4-5")
  println(@llm.Dialect::lower_context(d, ctx).stringify())
  println(@catalog.default_registry().labels().length())
}
