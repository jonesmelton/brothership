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
  /// Whatever an open demand needs, else what the ship asks, else
  /// cooperative.
  Dutiful
  /// Weighs arrival, hull, its own works and regard, and the ship's refits,
  /// for every post with and without a watch.
  Thoughtful
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
  Dutiful,
  Thoughtful,
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
    Dutiful => "dutiful"
    Thoughtful => "thoughtful"
  }
}

///|
pub let posts : Array[@core.Post] = [Drive, Hull, Craft]

///|
/// The crossing if `crew` took `post`, and stood a watch of `watch` ticks
/// when that is positive and allowed.
fn try_option(
  c : @core.Crossing,
  crew : Int32,
  post : @core.Post,
  watch : Int64,
) -> @core.Crossing {
  let c = c.apply(Posted(crew~, post~)) catch { _ => c }
  guard watch > 0L else { c }
  c.apply(Watched(crew~, ticks=watch)) catch {
    _ => c
  }
}

///|
/// What a check-in's choice leads to, if nothing else changes: the ends a
/// player can weigh against each other.
pub(all) struct Prospect {
  arrival : Int64
  hull : Int64
  work : Int64
  regard : Int64
  /// Refit levels plus progress, in work units.
  refit : Int64
} derive(Debug, Eq)

///|
fn refit_units(f : @core.Fit) -> Int64 {
  (f.baffles + f.plating + f.injectors) * 100L * @core.HOUR * @core.CRAFT_UNIT +
  f.progress
}

///|
pub fn prospect(c : @core.Crossing, crew : Int32) -> Prospect {
  let end = c.project().unwrap_or(c)
  let t = end.tallies.get(crew)
  {
    arrival: end.arrived_at.unwrap_or(@math.MAX_TICKS),
    hull: end.hull,
    work: t.map(t => t.work).unwrap_or(0L),
    regard: t.map(t => t.regard).unwrap_or(0L),
    refit: refit_units(end.fit),
  }
}

///|
/// How much one prospect is worth to a thoughtful player, in minutes of
/// arrival: an hour sooner is 60, a work is 90, a percent of hull is 4, an
/// hour of regard is 6 and a crew-hour of refit is 10.
fn Prospect::worth(self : Prospect) -> Int64 {
  -self.arrival / 60L +
  self.hull * 4L / (@core.HULL_FULL / 100L) +
  self.work * 90L / @core.WORK_SIZE +
  self.regard * 6L / @core.REGARD_HOUR +
  self.refit * 10L / (@core.HOUR * @core.CRAFT_UNIT)
}

///|
/// Differences smaller than these are not worth a player's attention: five
/// minutes of arrival, two percent of hull, a tenth of a work, half an hour
/// of regard, a crew-hour of refit.
fn Prospect::beats(self : Prospect, other : Prospect) -> Bool {
  let gains = [
    other.arrival - self.arrival >= 300L,
    self.hull - other.hull >= @core.HULL_FULL / 50L,
    self.work - other.work >= @core.WORK_SIZE / 10L,
    self.regard - other.regard >= @core.REGARD_HOUR / 2L,
    self.refit - other.refit >= @core.HOUR * @core.CRAFT_UNIT,
  ]
  let losses = [
    self.arrival - other.arrival >= 300L,
    other.hull - self.hull >= @core.HULL_FULL / 50L,
    other.work - self.work >= @core.WORK_SIZE / 10L,
    other.regard - self.regard >= @core.REGARD_HOUR / 2L,
    other.refit - self.refit >= @core.HOUR * @core.CRAFT_UNIT,
  ]
  gains.any(g => g) && !losses.any(l => l)
}

///|
/// Options no other option beats. Two or more mean the check-in offered a
/// real trade.
pub fn undominated(options : Array[Prospect]) -> Int {
  options.filter(o => !options.any(p => p.beats(o))).length()
}

///|
/// A check-in's choice: a post, and the length of watch to stand on it, or
/// zero for none.
pub(all) struct Choice {
  post : @core.Post
  watch : Int64
} derive(Debug, Eq)

///|
fn Policy::decide(
  self : Policy,
  c : @core.Crossing,
  crew : Int32,
  watch : Int64,
  roll : UInt64,
) -> Choice {
  let firing = c.firing()
  let post = (post : @core.Post) => { post, watch }
  let by_arrival = (later : Bool) => {
    let mut best = posts[0]
    let mut best_at = prospect(try_option(c, crew, best, watch), crew).arrival
    for p in posts[1:] {
      let at = prospect(try_option(c, crew, p, watch), crew).arrival
      if (later && at > best_at) || (!later && at < best_at) {
        best = p
        best_at = at
      }
    }
    post(best)
  }
  match self {
    Selfish => post(Craft)
    Driver => post(Drive)
    Mender => post(Hull)
    Cooperative => post(if firing { Drive } else { Craft })
    Careful =>
      post(
        if c.hull < @core.HULL_FULL / 2L {
          Hull
        } else if firing {
          Drive
        } else {
          Craft
        },
      )
    Random => post(posts[(roll % 3UL).to_int()])
    // Ties go to the post listed first, so these are deterministic.
    Hastener => by_arrival(false)
    Saboteur => by_arrival(true)
    Dutiful =>
      match open_post(c) {
        Some(p) => post(p)
        None =>
          match c.ask {
            Some(p) => post(p)
            None => post(if firing { Drive } else { Craft })
          }
      }
    Thoughtful => {
      let mut best = { post: Craft, watch: 0L }
      let mut best_worth = -(1L << 62)
      for p in posts {
        for w in [0L, watch] {
          let worth = prospect(try_option(c, crew, p, w), crew).worth()
          if worth > best_worth {
            best = { post: p, watch: w }
            best_worth = worth
          }
        }
      }
      best
    }
  }
}
