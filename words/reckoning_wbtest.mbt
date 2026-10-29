///|
test "time at the worlds coarsens, and agrees with its verb" {
  let day = 1.0 / 365.25
  let at : Array[Double] = [0.0, 0.5 * day, 3.0 * day, 40.0 * day, 1.0, 1.4, 2.6, 24.2]
  debug_inspect(
    at.map(passed_at_worlds),
    content=(
      #|[
      #|  "Under a day has passed",
      #|  "Under a day has passed",
      #|  "About 3 days have passed",
      #|  "About 1 month has passed",
      #|  "About 12 months have passed",
      #|  "About 17 months have passed",
      #|  "About 3 years have passed",
      #|  "About 24 years have passed",
      #|]
    ),
  )
}

///|
test "figures in the units research section 11 asks for" {
  let day = 1.0 / 365.25
  let ys : Array[Double] = [0.0, 30.0 / 525960.0, 3.0 / 8766.0, 5.0 * day, 0.25, 11.274]
  debug_inspect(
    ys.map(years_figure),
    content=(
      #|[
      #|  "0 minutes",
      #|  "30 minutes",
      #|  "3.0 hours",
      #|  "5.0 days",
      #|  "0.25 years",
      #|  "11.27 years",
      #|]

    ),
  )
  let ns : Array[Double] = [1.0, 1.2345, 9.994, 10.4, 999.6, 24000.4, 1234567.0]
  debug_inspect(
    ns.map(gamma_figure),
    content=(
      #|["1.00", "1.23", "9.99", "10", "1,000", "24,000", "1,234,567"]
    ),
  )
  let speeds : Array[Double] = [299792458.0, 1234.0, 3.2, 0.26, 0.0004]
  debug_inspect(
    speeds.map(speed_words),
    content=(
      #|["300,000 km", "1.23 km", "3.20 m", "26.0 cm", "0.400 mm"]
    ),
  )
  let evs : Array[Double] = [2.3, 1.1e5, 2.25e13]
  debug_inspect(
    evs.map(energy_figure),
    content=(
      #|["2.30 eV", "110 keV", "22.5 TeV"]
    ),
  )
  let angles : Array[Double] = [324000.0, 600.0, 8.6, 0.004]
  debug_inspect(
    angles.map(angle_figure),
    content=(
      #|["90.0°", "10.0′", "8.60″", "0.00400″"]
    ),
  )
}

///|
fn first_leg(drivers~ : Int) -> @core.State {
  let p = @ships.fleet()[0].profile
  let (_, s) = p.due(
    @core.State::initial(p.ship(seed=1), profile=p.name),
    1_800_000_000,
    officer=_ => true,
  )
  let (_, s) = p.due(s, 1_800_000_600, officer=_ => true)
  let mut s = s
  for i in 0..<drivers {
    s = s.apply(Crew(crew=i.to_string(), intent=Posted(post=Drive))) catch {
      _ => panic()
    }
  }
  s
}

///|
test "the reckoning and instruments mid-coast" {
  let s = first_leg(drivers=5)
  let c = s.crossing().unwrap()
  let s = s.apply(Tick(at=s.at + c.phase_ends().unwrap() + 3600L)) catch {
    _ => panic()
  }
  debug_inspect(
    reckoning_rows(s),
    content=(
      #|[
      #|  ("Aboard", "3 h 24 min"),
      #|  ("At the worlds", "3.35 years"),
      #|  ("Run", "3.350 ly from Kerala"),
      #|  ("To go", "12.354 ly to Occitan"),
      #|  ("Departure’s light leads by", "13.4 light-minutes"),
      #|]

    ),
  )
  debug_inspect(
    instrument_rows(s),
    content=(
      #|[
      #|  ("Lorentz factor γ", "24,000"),
      #|  ("Rapidity η", "10.78"),
      #|  ("Pace", "1 ly per 21.9 min aboard"),
      #|  ("Acceleration", "none, coasting"),
      #|  ("Light outruns the ship by", "26.0 cm a second"),
      #|  ("Occitan’s clocks, ahead", "48,000 times fast"),
      #|  ("Kerala’s clocks, behind", "48,000 times slow"),
      #|  ("Green light ahead arrives at", "110 keV"),
      #|  ("Half the sky lies within", "8.59″ of the bow"),
      #|  ("Each atom ahead strikes at", "22.5 TeV"),
      #|]

    ),
  )
}

///|
test "the next leg, from port" {
  let p = @ships.fleet()[0].profile
  let (_, s) = p.due(
    @core.State::initial(p.ship(seed=1), profile=p.name),
    1_800_000_000,
    officer=_ => true,
  )
  debug_inspect(
    next_leg_rows(s),
    content=(
      #|[
      #|  ("From", "Kerala, τ Ceti"),
      #|  ("To", "Occitan, 61 Cygni"),
      #|  ("Distance", "15.703 ly"),
      #|  ("At the worlds", "15.70 years"),
      #|  ("Aboard", "10.1 to 19.1 hours"),
      #|]

    ),
  )
}
