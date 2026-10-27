///|
fn counting(n : Ref[Int32]) -> @llm.Backend {
  @llm.Backend::new("counting", fn(c) {
    n.val += 1
    {
      model: c.model,
      text: "reply to \{c.user}",
      reasoning: None,
      finish: Some("stop"),
      usage: @llm.Usage::zero(),
      raw: Json::null(),
    }
  })
}

///|
fn call(user : String) -> @llm.Call {
  @llm.Call::new(model="m", system=["s"], user~, max_tokens=8)
}

///|
async test "live mode calls through once per distinct call" {
  let dir = @fs.tmpdir(prefix="llmcache")
  let n = Ref(0)
  let b = @cache.cached(counting(n), dir~)
  let first = b.call(call("a"))
  let again = b.call(call("a"))
  ignore(b.call(call("b")))
  assert_eq(first, again)
  assert_eq(n.val, 2)
}

///|
async test "cache survives a new wrapper over the same dir" {
  let dir = @fs.tmpdir(prefix="llmcache")
  let n = Ref(0)
  ignore(@cache.cached(counting(n), dir~).call(call("a")))
  let r = @cache.cached(counting(n), dir~, mode=Replay).call(call("a"))
  assert_eq(r.text, "reply to a")
  assert_eq(n.val, 1)
}

///|
async test "replay mode raises on a miss without calling through" {
  let dir = @fs.tmpdir(prefix="llmcache")
  let n = Ref(0)
  let b = @cache.cached(counting(n), dir~, mode=Replay)
  let missed = try {
    ignore(b.call(call("a")))
    false
  } catch {
    @cache.Miss(_) => true
    _ => false
  }
  assert_true(missed)
  assert_eq(n.val, 0)
}
