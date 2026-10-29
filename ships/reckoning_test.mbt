///|
/// The Tigress's first leg, Kerala to Occitan, with all five drive hands
/// it needs.
fn first_leg() -> @core.Crossing {
  let p = @ships.profiles()[1]
  let mut c = @core.Crossing::new(p.next_plan(legs=0, coils=0), p.ship(seed=1))
  for i in 0..<5 {
    c = c.apply(Posted(crew=i.to_string(), post=Drive)) catch { _ => panic() }
  }
  c
}

///|
fn fixed(x : Double, places : Int32) -> String {
  let scale = @fmath.pow(10.0, places.to_double())
  let n = (x * scale).round().to_int64()
  let whole = n / scale.to_int64()
  let part = (n % scale.to_int64()).to_string()
  guard places > 0 else { whole.to_string() }
  "\{whole}." + "0".repeat(places - part.length()) + part
}

///|
test "at departure the ship is at rest at Kerala, burning at full" {
  let r = @ships.reckon(first_leg())
  debug_inspect(
    (r.run, r.years, r.gamma(), fixed(r.accel, 0), fixed(r.length, 3)),
    content=(
      #|(0, 0, 1, "38000", "15.703")
    ),
  )
}

///|
test "at the cap, the sky, the light and the hull" {
  let c = first_leg()
  let coast = c.apply(Elapsed(ticks=c.phase_ends().unwrap() + 3600L)) catch {
    _ => panic()
  }
  let r = @ships.reckon(coast)
  debug_inspect(
    {
      "gamma": fixed(r.gamma(), 0),
      "eta": fixed(r.eta, 2),
      "accel": fixed(r.accel, 0),
      "minutes aboard per ly": fixed(r.pace(), 1),
      "light gains, m/s": fixed(r.shortfall(), 3),
      "doppler": fixed(r.doppler(), 0),
      "forward half-sky, arcsec": fixed(r.cone(), 1),
      "impact, TeV": fixed(r.impact() / 1.0e12, 1),
      "lead, light-minutes": fixed(r.lead * @ships.MINUTES_PER_YEAR, 1),
    },
    content=(
      #|{
      #|  "gamma": "24000",
      #|  "eta": "10.78",
      #|  "accel": "0",
      #|  "minutes aboard per ly": "21.9",
      #|  "light gains, m/s": "0.260",
      #|  "doppler": "48000",
      #|  "forward half-sky, arcsec": "8.6",
      #|  "impact, TeV": "22.5",
      #|  "lead, light-minutes": "13.4",
      #|}
    ),
  )
}

///|
test "law: across a crossing the ship only gains on Kerala and loses to light" {
  let mut c = first_leg()
  let mut last = @ships.reckon(c)
  let mut steps = 0
  while c.phase != Arrived {
    // Every boundary, and halfway to it.
    let step = (c.next_boundary() / 2L).max(1L)
    c = c.apply(Elapsed(ticks=step)) catch { _ => panic() }
    let r = @ships.reckon(c)
    assert_true(r.run >= last.run && r.years >= last.years, msg="\{c.t}")
    assert_true(r.lead >= last.lead && r.years >= r.run, msg="\{c.t}")
    assert_true((r.run + r.to_go() - r.length).abs() < 1.0e-9)
    last = r
    steps += 1
  }
  inspect(steps > 10, content="true")
  debug_inspect(
    (
      fixed(last.run, 3),
      fixed(last.years, 3),
      fixed(last.span, 3),
      fixed(last.lead * @ships.MINUTES_PER_YEAR, 1),
      last.gamma(),
    ),
    content=(
      #|("15.703", "15.703", "15.703", "26.8", 1)
    ),
  )
}
