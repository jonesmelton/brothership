///|
fn tigress_crossing() -> @core.Crossing {
  let p = @ships.profiles()[1]
  @core.Crossing::new(p.next_plan(legs=0, coils=0), p.ship(seed=1))
}

///|
fn spans(c : @core.Crossing) -> Array[(@core.Phase, Int64, Int64)] {
  stretches(c).map(s => (s.phase, s.width, s.done))
}

///|
test "a fresh crossing is all ahead, with burn and approach the same width" {
  let s = stretches(tigress_crossing())
  assert_eq(s.map(x => x.phase), [Burn, Coast, Approach])
  assert_eq(s.fold(init=0L, (n, x) => n + x.width), 1000L)
  assert_eq(s[0].width, s[2].width)
  assert_eq(s.map(x => x.done), [0L, 0L, 0L])
}

///|
test "the track fills the current phase by the share of its stock spent" {
  let c = tigress_crossing().apply(Elapsed(ticks=1800))
  let s = spans(c)
  assert_eq(c.phase, Burn)
  assert_true(s[0].2 > 0L && s[0].2 < 1000L)
  assert_eq(s[1].2, 0L)
}

///|
test "past phases are full" {
  let mut c = tigress_crossing()
  while c.phase == Burn {
    c = c.apply(Elapsed(ticks=600))
  }
  let s = spans(c)
  assert_eq(s[0].2, 1000L)
  assert_true(s[1].2 < 1000L)
  assert_eq(s[2].2, 0L)
}

///|
test "an arrived crossing is full" {
  let mut c = tigress_crossing()
  while c.phase != Arrived {
    c = c.apply(Elapsed(ticks=3600))
  }
  assert_eq(spans(c).map(x => x.2), [1000L, 1000L, 1000L])
}
