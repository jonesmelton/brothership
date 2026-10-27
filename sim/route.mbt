///|
/// One standard gravity in light-years per year squared.
const G : Double = 1.0323

///|
/// Seconds in a Julian year.
const YEAR : Double = 31557600.0

///|
/// A route and ship as a designer states them. `plan` turns it into the
/// integer `@core.Plan` the game runs on.
pub(all) struct Route {
  distance_ly : Double
  accel_g : Double
  gamma_cap : Double
  drive_needed : Int64
  /// Hull per tick at full burn, in `@core.HULL_FULL` units.
  wear : Int64
  /// Hull per tick per hand on the hull.
  repair : Int64
} derive(Debug, Eq)

///|
pub fn Route::default() -> Route {
  {
    distance_ly: 20.0,
    accel_g: 40000.0,
    gamma_cap: 24000.0,
    drive_needed: 4,
    wear: 30_000,
    repair: 28_000,
  }
}

///|
/// The ship's fittings at departure, before any refit.
pub fn Route::fit(self : Route) -> @core.Fit {
  @core.Fit::new(needed=self.drive_needed, wear=self.wear, repair=self.repair)
}

///|
/// The closed-form kinematics of `docs/gameplay.md`, at full burn, rounded
/// once into billionths. The only floating-point step between a route and
/// the game.
pub fn Route::plan(self : Route) -> @core.Plan {
  self.plan_with(coils=0)
}

///|
/// The plan for a ship with `coils` levels of coils: each raises the γ cap
/// by a fifth of the route's.
pub fn Route::plan_with(self : Route, coils~ : Int64) -> @core.Plan {
  let a = self.accel_g * G
  let cap = self.gamma_cap * (1.0 + coils.to_double() / 5.0)
  let eta = @fmath.acosh(1.0 + a * self.distance_ly / 2.0).min(
    @fmath.acosh(cap),
  )
  let gamma = @fmath.cosh(eta)
  let burn_d = (gamma - 1.0) / a
  let coast_d = (self.distance_ly - 2.0 * burn_d).max(0.0)
  let nano = (x : Double) => (x * 1.0e9).round().to_int64()
  {
    burn: nano(eta),
    coast: nano(coast_d),
    eta_rate: nano(a / YEAR),
    coast_rate: nano(@fmath.sinh(eta) / YEAR),
  }
}

///|
/// γ for a rapidity in billionths. Rendering only.
pub fn gamma(eta : Int64) -> Double {
  @fmath.cosh(eta.to_double() / 1.0e9)
}
