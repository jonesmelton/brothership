///|
fn sample() -> @llm.Call {
  @llm.Call::new(
    model="p:m",
    system=["frame", "setting"],
    user="entry",
    max_tokens=64,
  )
}

///|
fn reply(c : @llm.Call, text : String, finish~ : String = "stop") -> @llm.Reply {
  {
    model: c.model,
    text,
    reasoning: None,
    finish: Some(finish),
    usage: @llm.Usage::zero(),
    raw: Json::null(),
  }
}

///|
test "key is a stable sha256 of the call" {
  let k = sample().key()
  assert_eq(k.length(), 64)
  assert_eq(k, sample().key())
}

///|
test "key changes with any input, including the sample index" {
  let base = sample()
  for
    other in [
      { ..base, model: "q:m", },
      { ..base, system: ["frame setting"], },
      { ..base, temperature: Some(0.5), },
      { ..base, sample: 2, },
    ] {
    assert_true(other.key() != base.key())
  }
}

///|
test "reply round-trips through json" {
  let r : @llm.Reply = {
    model: "m",
    text: "hi",
    reasoning: Some("think"),
    finish: Some("stop"),
    usage: { input: 1, output: 2, reasoning: 1, cost_usd: 0.25, },
    raw: { "id": "x" },
  }
  let back : @llm.Reply = @json.from_json(r.to_json())
  assert_eq(back, r)
}

///|
async test "limited bounds calls in flight" {
  let in_flight = Ref(0)
  let peak = Ref(0)
  let slow = @llm.Backend::new("slow", async fn(c) {
    in_flight.val += 1
    peak.val = @cmp.maximum(peak.val, in_flight.val)
    @async.sleep(10)
    in_flight.val -= 1
    reply(c, "")
  })
  let b = slow.limited(2)
  @async.with_task_group(g => {
    for i in 0..<6 {
      g.spawn_bg(() => ignore(b.call(sample().with_user("\{i}"))))
    }
  })
  assert_eq(peak.val, 2)
}

///|
async test "route sends the bare model id to the named provider" {
  let seen = []
  let p = @llm.Backend::new("p", fn(c) {
    seen.push(c.model)
    reply(c, "ok")
  })
  let b = @llm.Backend::route({ "p": p })
  ignore(b.call(sample()))
  assert_eq(seen, ["m"])
  let unknown = try {
    ignore(b.call({ ..sample(), model: "zz:m", }))
    false
  } catch {
    @llm.LlmError::UnknownProvider(_) => true
    _ => false
  }
  assert_true(unknown)
}

///|
async test "retrying reruns empty and truncated replies" {
  let replies = ["", "cut off", "done"]
  let n = Ref(0)
  let flaky = @llm.Backend::new("flaky", fn(c) {
    let text = replies[n.val]
    n.val += 1
    reply(c, text, finish=if text == "cut off" { "length" } else { "stop" })
  })
  let r = flaky.retrying(max_retry=3, delay_ms=1).call(sample())
  assert_eq(r.text, "done")
  assert_eq(n.val, 3)
}

///|
async test "retrying gives up with the last error" {
  let empty = @llm.Backend::new("empty", fn(c) { reply(c, " \n") })
  let gave_up = try {
    ignore(empty.retrying(max_retry=2, delay_ms=1).call(sample()))
    false
  } catch {
    @llm.LlmError::Incomplete(_) => true
    _ => false
  }
  assert_true(gave_up)
}

///|
async test "retrying does not retry other errors" {
  let n = Ref(0)
  let broken = @llm.Backend::new("broken", fn(_) raise {
    n.val += 1
    fail("bad request")
  })
  ignore(
    broken.retrying(max_retry=3, delay_ms=1).call(sample()) catch {
      _ => reply(sample(), "")
    },
  )
  assert_eq(n.val, 1)
}
