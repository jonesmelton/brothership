///|
/// How a simulated crew member picks a post when it checks in.
pub(all) enum Policy {
  /// Always its craft.
  Selfish
  /// Always the drive.
  Driver
  /// Always the hull.
  Mender
  /// The drive while it fires, the craft in the coast.
  Cooperative
  /// Cooperative, but the hull whenever it is below half.
  Careful
  /// Any post, uniformly.
  Random
  /// Whichever post brings arrival soonest right now.
  Hastener
  /// Whichever post delays arrival most right now: an adversary.
  Saboteur
} derive(Debug, Eq, Compare, Hash, ToJson, FromJson)

///|
pub let policies : Array[Policy] = [
  Selfish,
  Driver,
  Mender,
  Cooperative,
  Careful,
  Random,
  Hastener,
  Saboteur,
]

///|
pub fn Policy::name(self : Policy) -> String {
  match self {
    Selfish => "selfish"
    Driver => "driver"
    Mender => "mender"
    Cooperative => "cooperative"
    Careful => "careful"
    Random => "random"
    Hastener => "hastener"
    Saboteur => "saboteur"
  }
}

///|
pub let posts : Array[@core.Post] = [Drive, Hull, Craft]

///|
/// Forecast arrival if `crew` took `post`.
fn forecast_with(c : @core.Crossing, crew : Int32, post : @core.Post) -> Int64 {
  let c = c.apply(Posted(crew~, post~)) catch { _ => c }
  c.forecast().unwrap_or(@math.MAX_TICKS)
}

///|
fn Policy::decide(
  self : Policy,
  c : @core.Crossing,
  crew : Int32,
  roll : UInt64,
) -> @core.Post {
  let firing = c.phase is (Burn | Approach)
  match self {
    Selfish => Craft
    Driver => Drive
    Mender => Hull
    Cooperative => if firing { Drive } else { Craft }
    Careful =>
      if c.hull < @core.HULL_FULL / 2L {
        Hull
      } else if firing {
        Drive
      } else {
        Craft
      }
    Random => posts[(roll % 3UL).to_int()]
    // Ties go to the post listed first, so these are deterministic.
    Hastener => {
      let mut best = posts[0]
      let mut best_at = forecast_with(c, crew, best)
      for post in posts[1:] {
        let at = forecast_with(c, crew, post)
        if at < best_at {
          best = post
          best_at = at
        }
      }
      best
    }
    Saboteur => {
      let mut worst = posts[0]
      let mut worst_at = forecast_with(c, crew, worst)
      for post in posts[1:] {
        let at = forecast_with(c, crew, post)
        if at > worst_at {
          worst = post
          worst_at = at
        }
      }
      worst
    }
  }
}
