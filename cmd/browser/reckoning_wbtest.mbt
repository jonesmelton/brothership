///|
test "at departure the voyage starts at γ one and the turns bound the plateau" {
  let c = tigress_crossing()
  let g = gamma_profile(c)
  assert_eq(g.now, 0L)
  assert_true(g.peak > 1.0)
  assert_true(g.burn_end > 0L && g.burn_end < g.approach_start)
  assert_eq(g.burn_end + g.approach_start, 1000L)
  // The hours aboard are sized as the track is.
  assert_eq(g.burn_end, stretches(c)[0].width)
}

///|
test "γ stays near one for most of the burn and climbs at its end" {
  let g = gamma_profile(tigress_crossing())
  let curve = gamma_curve(g)
  let rise = curve[:BURN_SAMPLES + 1].to_owned()
  assert_eq(rise[0], (0L, PROFILE_BASE))
  assert_eq(rise[BURN_SAMPLES], (g.burn_end, PROFILE_TOP))
  for i in 1..<rise.length() {
    assert_true(rise[i].1 <= rise[i - 1].1)
  }
  // Halfway through the burn's hours γ is still under 1% of the peak.
  let half = rise[BURN_SAMPLES / 2].1
  let height = (PROFILE_BASE - PROFILE_TOP).to_double()
  assert_true((PROFILE_BASE - half).to_double() < 0.01 * height)
  // The approach mirrors the burn and ends at one.
  assert_eq(curve[curve.length() - 1], (1000L, PROFILE_BASE))
  assert_eq(curve[BURN_SAMPLES + 1], (g.approach_start, PROFILE_TOP))
}

///|
test "mid-coast the ship is on the plateau, between the turns" {
  let mut c = tigress_crossing()
  while c.phase == Burn {
    c = c.apply(Elapsed(ticks=600))
  }
  let c = c.apply(Elapsed(ticks=7200))
  let g = gamma_profile(c)
  assert_true(g.now > g.burn_end && g.now < g.approach_start)
  assert_true(g.now_gamma > 0.9 * g.peak)
}

///|
test "arrived is the end of the voyage, back at γ one" {
  let mut c = tigress_crossing()
  while c.phase != Arrived {
    c = c.apply(Elapsed(ticks=3600))
  }
  let g = gamma_profile(c)
  assert_eq(g.now, 1000L)
  assert_true(g.now_gamma < 1.000001)
}

///|
test "the chart puts γ one at the base and the peak at the top" {
  assert_eq(chart_y(1.0, 24_000.0), PROFILE_BASE)
  assert_eq(chart_y(24_000.0, 24_000.0), PROFILE_TOP)
  assert_eq(chart_y(1.0, 1.0), PROFILE_BASE)
  assert_true(chart_y(12_000.0, 24_000.0) < PROFILE_BASE)
}

///|
test "aberration moves the sky ahead inward by the rapidity" {
  // A star abeam at the worlds lands where the reckoning's cone says.
  let eta = 10.78
  let r : @ships.Reckoning = {
    run: 0.0,
    length: 1.0,
    years: 0.0,
    span: 1.0,
    burn_span: 0.0,
    eta,
    accel: 0.0,
    lead: 0.0,
  }
  let abeam = sky_angle(sky_u(0.0) - eta)
  assert_true((abeam * 3600.0 - r.cone()).abs() < 1.0e-6 * r.cone())
  // Dead ahead stays ahead; nothing crosses the bow.
  assert_true(sky_u(0.999) - eta < sky_u(0.0) - eta)
}

///|
test "the bow sight's scale fits the crossing, rest at the rim and peak near the bow" {
  let scale = SkyScale::new(10.78)
  let rest = scale.radius(sky_u(0.0)).unwrap()
  let peak = scale.radius(sky_u(0.0) - 10.78).unwrap()
  assert_true(rest > 0.6 && rest < 1.0)
  assert_true(peak > 0.0 && peak < 0.35)
  // Behind the stern and past the bow's floor are off the sight.
  assert_eq(scale.radius(sky_u(-0.9999)), None)
  assert_eq(scale.radius(-40.0), None)
}

///|
test "the star field is fixed, and half of it lies ahead" {
  let a = sky_stars()
  let b = sky_stars()
  assert_eq(a.length(), b.length())
  for i in 0..<a.length() {
    assert_true(a[i].u == b[i].u && a[i].bearing == b[i].bearing)
  }
  let ahead = a.filter(s => s.u < 0.0).length()
  assert_true((ahead - a.length() / 2).abs() <= a.length() / 10)
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
  let (sx, _) = frame.place(ship_on_map(c, from, to))
  let (fx, _) = frame.place(from.on_map())
  let (tx, _) = frame.place(to.on_map())
  // Kerala lies east of Occitan on the map, so the ship is between them.
  assert_true(sx < fx && sx > tx)
}
