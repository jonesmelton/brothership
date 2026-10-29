// The crossing as the worlds see it: rendering only. Distance and time at
// the worlds follow from the plan's rapidity and stock in closed form, as in
// docs/gameplay.md, so a burn short of full covers the plan's distance in
// more hours aboard, which is the approximation the plan already makes.

///|
/// The speed of light, in metres per second.
const C : Double = 299792458.0

///|
/// A proton's rest energy in electronvolts: the interstellar medium is
/// mostly hydrogen.
const PROTON : Double = 938272088.0

///|
/// Minutes in a Julian year: a light-year in light-minutes.
pub const MINUTES_PER_YEAR : Double = 525960.0

///|
/// Where a crossing stands in the worlds' frame. Origin and destination are
/// at rest in it, so "years" passed alike at both.
pub(all) struct Reckoning {
  /// Light-years from the origin, and the leg's length.
  run : Double
  length : Double
  /// Years passed at the worlds since departure, and over the whole
  /// crossing.
  years : Double
  span : Double
  /// Years at the worlds that one burn takes, the same for the approach.
  burn_span : Double
  /// Rapidity now.
  eta : Double
  /// Proper acceleration now, in g: none while coasting.
  accel : Double
  /// Light-years by which the light that left the origin at departure
  /// leads the ship: years less run.
  lead : Double
} derive(Debug)

///|
/// `(1 - e^-η) / a`: time less distance at the worlds over a burn from
/// rest to `eta`.
fn burn_lead(eta : Double, a : Double) -> Double {
  -@fmath.expm1(-eta) / a
}

///|
/// Distance over a burn from rest to `eta`: `(cosh η - 1) / a`, written so
/// it keeps its digits near rest.
fn burn_run(eta : Double, a : Double) -> Double {
  let s = @fmath.sinh(eta / 2.0)
  2.0 * s * s / a
}

///|
/// Years less light-years over a coast of `d` light-years at `eta`:
/// `d (1/β - 1)`.
fn coast_lead(d : Double, eta : Double) -> Double {
  d * 2.0 / @fmath.expm1(2.0 * eta)
}

///|
/// Years at the worlds over the whole of `plan`, the `span` of `reckon`.
pub fn span_of(plan : @core.Plan) -> Double {
  let top = plan.burn.to_double() / 1.0e9
  let a = plan.eta_rate.to_double() * YEAR / 1.0e9
  let coast = plan.coast.to_double() / 1.0e9
  let coast_lag = if coast > 0.0 { coast_lead(coast, top) } else { 0.0 }
  burn_run(top, a) * 2.0 + coast + burn_lead(top, a) * 2.0 + coast_lag
}

///|
pub fn reckon(c : @core.Crossing) -> Reckoning {
  let plan = c.plan
  let top = plan.burn.to_double() / 1.0e9
  // Full-burn acceleration in light-years per year squared.
  let a = plan.eta_rate.to_double() * YEAR / 1.0e9
  let coast = plan.coast.to_double() / 1.0e9
  let burned = burn_run(top, a)
  let length = burned * 2.0 + coast
  let coast_lag = if coast > 0.0 { coast_lead(coast, top) } else { 0.0 }
  let full_lead = burn_lead(top, a) * 2.0 + coast_lag
  let eta = c.eta().to_double() / 1.0e9
  let (run, lead) = match c.phase {
    Burn => (burn_run(eta, a), burn_lead(eta, a))
    Coast => {
      let d = coast - c.left.to_double() / 1.0e9
      (burned + d, burn_lead(top, a) + coast_lead(d, top))
    }
    Approach => (length - burn_run(eta, a), full_lead - burn_lead(eta, a))
    Arrived => (length, full_lead)
  }
  let accel = if c.firing() {
    a / G * c.setting().to_double() / @math.SETTING_FULL.to_double()
  } else {
    0.0
  }
  {
    run,
    length,
    years: run + lead,
    span: length + full_lead,
    burn_span: burned + burn_lead(top, a),
    eta,
    accel,
    lead,
  }
}

///|
pub fn Reckoning::to_go(self : Reckoning) -> Double {
  self.length - self.run
}

///|
/// The Lorentz factor: hours passing at the worlds for each hour aboard.
pub fn Reckoning::gamma(self : Reckoning) -> Double {
  @fmath.cosh(self.eta)
}

///|
/// Minutes aboard per light-year run, 1/sinh η of a year; infinite at rest.
pub fn Reckoning::pace(self : Reckoning) -> Double {
  MINUTES_PER_YEAR / @fmath.sinh(self.eta)
}

///|
/// How fast light outruns the ship, in metres per second: c(1 - β).
pub fn Reckoning::shortfall(self : Reckoning) -> Double {
  C * 2.0 / (@fmath.exp(2.0 * self.eta) + 1.0)
}

///|
/// The Doppler factor dead ahead, e^η: how much faster clocks ahead seem
/// to run, and how much bluer their light. Those behind seem as much slower.
pub fn Reckoning::doppler(self : Reckoning) -> Double {
  @fmath.exp(self.eta)
}

///|
/// In arcseconds, how close to the bow aberration crowds what the worlds
/// see as the forward half of the sky: 2 atan(e^-η).
pub fn Reckoning::cone(self : Reckoning) -> Double {
  2.0 * @fmath.atan(@fmath.exp(-self.eta)) * 180.0 / @fmath.PI * 3600.0
}

///|
/// The energy, in electronvolts, with which each hydrogen nucleus ahead
/// strikes the hull: (γ - 1) of a proton's rest energy.
pub fn Reckoning::impact(self : Reckoning) -> Double {
  let s = @fmath.sinh(self.eta / 2.0)
  2.0 * s * s * PROTON
}
