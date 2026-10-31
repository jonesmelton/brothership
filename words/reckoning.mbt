// The crossing as the worlds see it, in words and figures. Sentences
// coarsen and do not tick; the figures in the tables do, and are read only
// on demand. Units follow research/liveship-travel-math.md, section 11.

///|
fn possessive(name : String) -> String {
  if name.has_suffix("s") {
    name + "’"
  } else {
    name + "’s"
  }
}

///|
/// `x` to `places` decimals, `x` at least 0.
fn fixed(x : Double, places : Int32) -> String {
  let scale = @fmath.pow(10.0, places.to_double()).to_int64()
  let n = (x * scale.to_double()).round().to_int64()
  guard places > 0 else { grouped(n) }
  let part = (n % scale).to_string()
  "\{grouped(n / scale)}." + "0".repeat(places - part.length()) + part
}

///|
/// `x` to `places` decimals, grouped: a figure for a label beside a drawing.
pub fn figure(x : Double, places : Int32) -> String {
  fixed(x, places)
}

///|
/// A whole number with thousands separated by commas.
fn grouped(n : Int64) -> String {
  let digits = n.to_string()
  let out = StringBuilder()
  for i, ch in digits {
    if i > 0 && (digits.length() - i) % 3 == 0 {
      out.write_char(',')
    }
    out.write_char(ch)
  }
  out.to_string()
}

///|
/// `x` to three significant figures, grouped from a thousand up.
fn sig3(x : Double) -> String {
  guard x > 0.0 else { "0" }
  let digits = @fmath.floor(@fmath.log10(x)).to_int()
  if digits >= 2 {
    let unit = @fmath.pow(10.0, (digits - 2).to_double())
    grouped(((x / unit).round() * unit).to_int64())
  } else {
    fixed(x, 2 - digits)
  }
}

///|
/// Time passed at the worlds, coarse: the opening of a sentence, with its
/// verb.
fn passed_at_worlds(years : Double) -> String {
  let days = years * 365.25
  let (n, unit, units) = if days < 1.0 {
    return "Under a day has passed"
  } else if years < 0.1 {
    (days.round(), "day", "days")
  } else if years < 1.5 {
    ((years * 12.0).round(), "month", "months")
  } else {
    (years.round(), "year", "years")
  }
  if n == 1.0 {
    "About 1 \{unit} has passed"
  } else {
    "About \{n.to_int64()} \{units} have passed"
  }
}

///|
/// Time at the worlds as a figure: minutes under an hour, hours under a
/// day, days under a tenth of a year, then years to two decimals.
fn years_figure(years : Double) -> String {
  let minutes = years * @ships.MINUTES_PER_YEAR
  if minutes < 60.0 {
    "\{fixed(minutes, 0)} minutes"
  } else if minutes < 1440.0 {
    "\{fixed(minutes / 60.0, 1)} hours"
  } else if years < 0.1 {
    "\{fixed(years * 365.25, 1)} days"
  } else {
    "\{fixed(years, 2)} years"
  }
}

///|
/// γ: a grouped whole number, or two decimals below 10.
fn gamma_figure(gamma : Double) -> String {
  if gamma < 10.0 {
    fixed(gamma, 2)
  } else {
    fixed(gamma, 0)
  }
}

///|
/// A distance in metres in the unit that keeps it readable.
fn speed_words(metres : Double) -> String {
  if metres >= 1000.0 {
    "\{sig3(metres / 1000.0)} km"
  } else if metres >= 1.0 {
    "\{sig3(metres)} m"
  } else if metres >= 0.01 {
    "\{sig3(metres * 100.0)} cm"
  } else {
    "\{sig3(metres * 1000.0)} mm"
  }
}

///|
fn energy_figure(ev : Double) -> String {
  let units = ["eV", "keV", "MeV", "GeV", "TeV", "PeV", "EeV"]
  let mut x = ev
  let mut i = 0
  while x >= 1000.0 && i < units.length() - 1 {
    x = x / 1000.0
    i += 1
  }
  "\{sig3(x)} \{units[i]}"
}

///|
/// An angle given in arcseconds, in degrees, arcminutes or arcseconds.
pub fn angle_figure(arcsec : Double) -> String {
  if arcsec >= 3600.0 {
    "\{sig3(arcsec / 3600.0)}°"
  } else if arcsec >= 60.0 {
    "\{sig3(arcsec / 60.0)}′"
  } else {
    "\{sig3(arcsec)}″"
  }
}

///|
/// Ticks aboard as hours and minutes.
fn aboard_figure(ticks : Int64) -> String {
  let minutes = ticks / 60L
  if minutes < 60L {
    "\{minutes} min"
  } else {
    "\{minutes / 60L} h \{minutes % 60L} min"
  }
}

///|
/// Photon energy of green light, 540 nm, in electronvolts.
const GREEN : Double = 2.3

///|
/// The distance and the time at the worlds, as sentences, for
/// `where_sentences`. Nothing once arrived.
fn reckoning_sentences(c : @core.Crossing, s : @core.State) -> Array[String] {
  guard c.phase != Arrived else { [] }
  let (from, to) = (@ships.origin(s.ship), destination(s))
  let r = @ships.reckon(c)
  [
    "\{fixed(r.to_go(), 1)} of the \{fixed(r.length, 1)} light-years from \{from.name} still to go.",
    "\{passed_at_worlds(r.years)} at \{from.name} and \{to.name} since departure.",
  ]
}

///|
/// When the phase under way gives way to the next, as a sentence. The
/// approach has none: it ends in arrival, which has its own.
fn turn_sentence(c : @core.Crossing) -> Array[String] {
  let next = match c.phase {
    Burn if c.plan.coast > 0L => "coast"
    Burn | Coast => "approach"
    Approach | Arrived => return []
  }
  match c.phase_ends() {
    Some(at) => ["The \{next} begins \{in_words(at - c.t)}."]
    None => []
  }
}

///|
/// Where the crossing stands at the worlds, as label and figure: the two
/// clocks, the distance, and the light of departure. Empty in port.
pub fn reckoning_rows(s : @core.State) -> Array[(String, String)] {
  guard s.crossing() is Some(c) else { [] }
  let (from, to) = (@ships.origin(s.ship), destination(s))
  let r = @ships.reckon(c)
  [
    ("Aboard", aboard_figure(c.arrived_at.unwrap_or(c.t))),
    ("At the worlds", years_figure(r.years)),
    ("Run", "\{fixed(r.run, 3)} ly from \{from.name}"),
    ("To go", "\{fixed(r.to_go(), 3)} ly to \{to.name}"),
    (
      "Departure’s light leads by",
      "\{sig3(r.lead * @ships.MINUTES_PER_YEAR)} light-minutes",
    ),
  ]
}

///|
/// What the ship's instruments read, as label and figure. Empty in port
/// and once arrived.
pub fn instrument_rows(s : @core.State) -> Array[(String, String)] {
  guard s.crossing() is Some(c) && c.phase != Arrived else { [] }
  let (from, to) = (@ships.origin(s.ship), destination(s))
  let r = @ships.reckon(c)
  let pace = r.pace()
  let pace = if pace > 2.0 * @ships.MINUTES_PER_YEAR {
    "over 2 years aboard per ly"
  } else if pace >= 1440.0 {
    "1 ly per \{sig3(pace / 1440.0)} days aboard"
  } else if pace >= 60.0 {
    "1 ly per \{sig3(pace / 60.0)} h aboard"
  } else {
    "1 ly per \{sig3(pace)} min aboard"
  }
  let accel = if r.accel > 0.0 {
    "\{sig3(r.accel)} g"
  } else {
    "none, coasting"
  }
  let times = sig3(r.doppler())
  [
    ("Peak Lorentz factor γ", gamma_figure(@ships.gamma(c.plan.burn))),
    ("Lorentz factor γ", gamma_figure(r.gamma())),
    ("Rapidity η", fixed(r.eta, 2)),
    ("Pace", pace),
    ("Acceleration", accel),
    ("Light outruns the ship by", "\{speed_words(r.shortfall())} a second"),
    ("\{possessive(to.name)} clocks, ahead", "\{times} times fast"),
    ("\{possessive(from.name)} clocks, behind", "\{times} times slow"),
    ("Green light ahead arrives at", energy_figure(GREEN * r.doppler())),
    ("Half the sky lies within", "\{angle_figure(r.cone())} of the bow"),
    ("Each atom ahead strikes at", energy_figure(r.impact())),
  ]
}

///|
/// The leg the ship departs on next, as label and figure. Empty underway;
/// only where it leaves from until the ship chooses where it goes.
pub fn next_leg_rows(s : @core.State) -> Array[(String, String)] {
  guard s.leg is InPort(_) else { [] }
  let from = @ships.origin(s.ship)
  guard @ships.bound_for(s) is Some(to) else {
    [("From", "\{from.name}, \{from.star}"), ("To", "not chosen yet")]
  }
  let distance_ly = from.distance_to(to)
  let rows = [
    ("From", "\{from.name}, \{from.star}"),
    ("To", "\{to.name}, \{to.star}"),
    ("Distance", "\{fixed(distance_ly, 3)} ly"),
  ]
  guard @ships.profile_named(s.profile) is Some(p) else { rows }
  let plan = p.next_plan(
    distance_ly~,
    coils=s.ship.fit.coils,
    cruise=s.ship.cruise,
  )
  let r = @ships.reckon(@core.Crossing::new(plan, s.ship))
  let hours = (ticks : Int64) => fixed(ticks.to_double() / 3600.0, 1)
  rows +
  [
    ("At the worlds", years_figure(r.span)),
    ("Aboard", "\{hours(plan.fastest())} to \{hours(plan.slowest())} hours"),
  ]
}
