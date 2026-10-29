///|
test "at departure both scales start at zero, and the burn is a sliver of the worlds' years" {
  let n = nomogram(tigress_crossing())
  assert_eq((n.aboard.now, n.worlds.now), (0L, 0L))
  assert_eq(n.aboard.burn_end, stretches(tigress_crossing())[0].width)
  // About 20% of the hours aboard, under 4% of the years at the worlds.
  assert_true(n.aboard.burn_end > 150L && n.worlds.burn_end < 40L)
  assert_eq(n.aboard.burn_end + n.aboard.approach_start, 1000L)
  assert_eq(n.worlds.burn_end + n.worlds.approach_start, 1000L)
}

///|
test "mid-coast the ship is between the turns on both scales" {
  let mut c = tigress_crossing()
  while c.phase == Burn {
    c = c.apply(Elapsed(ticks=600))
  }
  let c = c.apply(Elapsed(ticks=7200))
  let n = nomogram(c)
  for scale in [n.aboard, n.worlds] {
    assert_true(scale.now > scale.burn_end && scale.now < scale.approach_start)
  }
}

///|
test "arrived is the end of both scales" {
  let mut c = tigress_crossing()
  while c.phase != Arrived {
    c = c.apply(Elapsed(ticks=3600))
  }
  let n = nomogram(c)
  assert_eq((n.aboard.now, n.worlds.now), (1000L, 1000L))
}

///|
test "the profile splits at the ship into flown and still to fly" {
  let (flown, ahead) = split_profile(
    [(0L, 100L), (200L, 0L), (800L, 0L), (1000L, 100L)],
    500L,
  )
  debug_inspect(
    (flown, ahead),
    content=(
      #|([(0, 100), (200, 0), (500, 0)], [(500, 0), (800, 0), (1000, 100)])
    ),
  )
  let (flown, ahead) = split_profile([(0L, 100L), (200L, 0L)], 100L)
  debug_inspect(
    (flown, ahead),
    content=(
      #|([(0, 100), (100, 50)], [(100, 50), (200, 0)])
    ),
  )
}

///|
test "the map frames every world and the Sun, and puts the ship on its leg" {
  let frame = map_frame()
  for w in @ships.worlds {
    let (x, y) = frame.place(w.on_map())
    assert_true(x > 0L && x < 1000L && y > 0L && y < frame.height, msg=w.name)
  }
  let mut c = tigress_crossing()
  while c.phase == Burn {
    c = c.apply(Elapsed(ticks=600))
  }
  let (from, to) = @ships.leg(0)
  let (sx, _) = frame.place(ship_on_map(c, 0))
  let (fx, _) = frame.place(from.on_map())
  let (tx, _) = frame.place(to.on_map())
  // Kerala lies east of Occitan on the map, so the ship is between them.
  assert_true(sx < fx && sx > tx)
}
