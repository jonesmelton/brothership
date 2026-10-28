///|
let policy = "the policy"

///|
fn gate() -> @gate.Gate {
  @gate.Gate::new(model="meta:muse-spark-1.3", policy~)
}

///|
test "a message is wrapped in a tag whose id comes from its text" {
  let wrapped = @gate.wrap("hello")
  let id = @llm.sha256_hex("hello")[0:12].to_owned()
  assert_eq(wrapped, "<message id=\{id}>\nhello\n</message id=\{id}>")
  assert_true(@gate.wrap("hello!") != wrapped)
}

///|
test "the call carries the policy as system and the wrapped message as user" {
  let c = gate().call("hello")
  assert_eq(c.model, "meta:muse-spark-1.3")
  assert_eq(c.system, [policy])
  assert_eq(c.user, @gate.wrap("hello"))
  assert_eq(c.reasoning_effort, Some("medium"))
}

///|
test "a verdict is decoded from the reply" {
  assert_eq(@gate.decode("{\"violation\": 0, \"evidence\": \"\"}"), @gate.Clean)
  assert_eq(
    @gate.decode(
      "Verdict:\n{\"violation\": 1, \"evidence\": \"the {red} deck\"}\n",
    ),
    @gate.Violation("the {red} deck"),
  )
  assert_eq(@gate.decode("{\"violation\": 1}"), @gate.Violation(""))
}

///|
test "a reply without a verdict is an error" {
  for
    reply in [
      "I can't help with that.", "{\"violation\": 2}", "{\"evidence\": \"x\"}", "{\"violation\": 1",
    ] {
    let unreadable = try {
      ignore(@gate.decode(reply))
      false
    } catch {
      @gate.Unreadable(_) => true
    }
    assert_true(unreadable, msg=reply)
  }
}

///|
async test "check sends the call and decodes the reply" {
  let seen : Ref[@llm.Call?] = Ref(None)
  let backend = @llm.Backend::new("fixed", fn(c) {
    seen.val = Some(c)
    {
      model: c.model,
      text: "{\"violation\": 1, \"evidence\": \"gore\"}",
      reasoning: None,
      finish: Some("stop"),
      usage: @llm.Usage::zero(),
      raw: Json::null(),
    }
  })
  assert_eq(gate().check(backend, "gore"), @gate.Violation("gore"))
  assert_eq(seen.val, Some(gate().call("gore")))
}

///|
async test "clear passes clean text and raises on a violation" {
  let reply = (verdict : String) => {
    @llm.Backend::new("fixed", fn(c) {
      {
        model: c.model,
        text: verdict,
        reasoning: None,
        finish: Some("stop"),
        usage: @llm.Usage::zero(),
        raw: Json::null(),
      }
    })
  }
  let clean = reply("{\"violation\": 0}")
  inspect(gate().clear(clean, "hello").text(), content="hello")
  let blocked = try {
    ignore(gate().clear(reply("{\"violation\": 1, \"evidence\": \"x\"}"), "x"))
    ""
  } catch {
    @gate.Blocked(e) => e
    _ => "other"
  }
  inspect(blocked, content="x")
}
