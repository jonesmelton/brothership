///|
fn sample() -> @llm.Call {
  @llm.Call::new(
    model="m",
    system=["frame", "setting"],
    user="entry",
    max_tokens=64,
  )
}

///|
test "key is a stable sha256 of the call" {
  let k = sample().key()
  assert_eq(k.length(), 64)
  assert_eq(k, sample().key())
}

///|
test "key changes with any input" {
  let base = sample().key()
  assert_true(
    @llm.Call::new(
      model="n",
      system=["frame", "setting"],
      user="entry",
      max_tokens=64,
    ).key() !=
    base,
  )
  assert_true(
    @llm.Call::new(
      model="m",
      system=["frame setting"],
      user="entry",
      max_tokens=64,
    ).key() !=
    base,
  )
  assert_true(
    @llm.Call::new(
      model="m",
      system=["frame", "setting"],
      user="entry",
      max_tokens=64,
      temperature=0.5,
    ).key() !=
    base,
  )
}

///|
test "reply round-trips through json" {
  let r = @llm.Reply::{
    model: "m",
    text: "hi",
    reasoning: Some("think"),
    usage: { input: 1, output: 2, reasoning: 1, cost_usd: 0.25, },
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
    @llm.Reply::{
      model: c.model,
      text: "",
      reasoning: None,
      usage: @llm.Usage::zero(),
    }
  })
  let b = slow.limited(2)
  @async.with_task_group(g => {
    for i in 0..<6 {
      g.spawn_bg(() => ignore(b.call(sample().with_user("\{i}"))))
    }
  })
  assert_eq(peak.val, 2)
}
