///|
test "elapsed advances the clock" {
  debug_inspect(
    @core.State::initial().apply(Elapsed(ticks=3)).apply(Elapsed(ticks=4)),
    content="{ clock: 7 }",
  )
}

///|
test "rejections" {
  let reject = (state : @core.State, event) => {
    try state.apply(event) catch {
      err => err
    } noraise {
      _ => fail("expected a rejection")
    }
  }
  debug_inspect(
    reject(@core.State::initial(), Elapsed(ticks=0)),
    content="NonPositiveTicks(ticks=0)",
  )
  let edge : @core.State = { clock: @math.MAX_CLOCK - 1, }
  debug_inspect(
    reject(edge, Elapsed(ticks=2)),
    content=(
      #|ClockOverflow(clock=9223372036854775806, ticks=2)
    ),
  )
  debug_inspect(
    edge.apply(Elapsed(ticks=1)),
    content=(
      #|{ clock: 9223372036854775807 }
    ),
  )
}

///|
test "the clock runs past 32 bits" {
  let edge : @core.State = { clock: 2147483647, }
  debug_inspect(edge.apply(Elapsed(ticks=1)), content="{ clock: 2147483648 }")
}

///|
test "wire format" {
  json_inspect(
    @core.Receipt::Refused(id=2, reason=NonPositiveTicks(ticks=-1), snapshot={
      seq: 5,
      state: { clock: 9, },
    }),
    content=[
      "Refused",
      {
        "id": "2",
        "reason": ["NonPositiveTicks", { "ticks": "-1" }],
        "snapshot": { "seq": "5", "state": { "clock": "9" } },
      },
    ],
  )
}

///|
test "wire format round trips" {
  let receipt = @core.Receipt::Accepted(id=1, snapshot={
    seq: 1,
    state: { clock: 1, },
  })
  let decoded : @core.Receipt = @json.from_json(receipt.to_json())
  assert_eq(decoded, receipt)
}

///|
test "replay" {
  debug_inspect(
    @core.replay([@core.Elapsed(ticks=1), @core.Elapsed(ticks=2)].iter()),
    content="{ clock: 3 }",
  )
}
