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
  /// Cooperative, but the hull from below half until three quarters.
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
  /// Ship posts only: an open demand's, else what the ship asks for, else
  /// the drive while it fires and the hull otherwise. How recruits work.
  Steady
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
  Steady,
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
    Steady => "steady"
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
  crew : String,
  post : @core.Post,
  watch : Int64,
  order~ : @core.Order? = None,
) -> @core.Crossing {
  let c = c.apply(Posted(crew~, post~)) catch { _ => c }
  let c = c.apply(Ordered(crew~, order~)) catch { _ => c }
  guard watch > 0L else { c }
  c.apply(Watched(crew~, ticks=watch)) catch {
    _ => c
  }
}

///|
/// The order a cooperative crew member leaves: to their craft when the
/// coast begins, and back to the drive at turnover.
pub fn handover(c : @core.Crossing) -> @core.Order? {
  match c.phase {
    Burn if c.plan.coast > 0L => Some({ phase: Coast, post: Craft, })
    Coast => Some({ phase: Approach, post: Drive, })
    _ => None
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
  (f.baffles + f.plating + f.injectors + f.coils) *
  100L *
  @core.HOUR *
  @core.CRAFT_UNIT +
  f.progress
}

///|
pub fn prospect(c : @core.Crossing, crew : String) -> Prospect {
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
/// Differences smaller than these are not worth a player's attention: a
/// quarter hour of arrival, five percent of hull, a quarter of a work, an
/// hour of regard, two crew-hours of refit.
fn Prospect::beats(self : Prospect, other : Prospect) -> Bool {
  let gains = [
    other.arrival - self.arrival >= 900L,
    self.hull - other.hull >= @core.HULL_FULL / 20L,
    self.work - other.work >= @core.WORK_SIZE / 4L,
    self.regard - other.regard >= @core.REGARD_HOUR,
    self.refit - other.refit >= 2L * @core.HOUR * @core.CRAFT_UNIT,
  ]
  let losses = [
    self.arrival - other.arrival >= 900L,
    other.hull - self.hull >= @core.HULL_FULL / 20L,
    other.work - self.work >= @core.WORK_SIZE / 4L,
    other.regard - self.regard >= @core.REGARD_HOUR,
    other.refit - self.refit >= 2L * @core.HOUR * @core.CRAFT_UNIT,
  ]
  gains.any(g => g) && !losses.any(l => l)
}

///|
/// Options no other option beats. Two or more mean the check-in offered a
/// real trade.
pub fn undominated(options : Array[Prospect]) -> Int32 {
  options.filter(o => !options.any(p => p.beats(o))).length()
}

///|
/// A check-in's choice: a post, the length of watch to stand on it or zero
/// for none, and a standing order for the next phase.
pub(all) struct Choice {
  post : @core.Post
  watch : Int64
  order : @core.Order?
} derive(Debug, Eq)

///|
/// Whether `crew` should be on the hull: below `low`, or already mending
/// and short of three quarters. The gap keeps a crew member from changing
/// post at every band edge.
fn mending(c : @core.Crossing, crew : String, low : Int64) -> Bool {
  let on_hull = c.hands.get(crew).map(h => h.post == Hull).unwrap_or(false)
  c.hull < low || (on_hull && c.hull < @core.HULL_FULL * 3L / 4L)
}

///|
fn Policy::decide(
  self : Policy,
  c : @core.Crossing,
  crew : String,
  watch : Int64,
  roll : UInt64,
) -> Choice {
  let firing = c.firing()
  let post = (post : @core.Post) => { post, watch, order: None, }
  let handing = (post : @core.Post) => { post, watch, order: handover(c), }
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
    Cooperative => handing(if firing { Drive } else { Craft })
    Careful =>
      handing(
        if mending(c, crew, @core.HULL_FULL / 2L) {
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
        Some(p) => handing(p)
        None =>
          match c.ask {
            Some(p) => handing(p)
            None => handing(if firing { Drive } else { Craft })
          }
      }
    Steady => {
      let ship_post = (p : @core.Post?) => p.filter(p => p != Craft)
      match (ship_post(open_post(c)), ship_post(c.ask)) {
        (Some(p), _) | (None, Some(p)) => post(p)
        (None, None) => post(if firing { Drive } else { Hull })
      }
    }
    Thoughtful => {
      let mut best = { post: Craft, watch: 0L, order: None, }
      let mut best_worth = -(1L << 62)
      for p in posts {
        for w in [0L, watch] {
          for order in [None, handover(c)] {
            let option = try_option(c, crew, p, w, order~)
            let worth = prospect(option, crew).worth()
            if worth > best_worth {
              best = { post: p, watch: w, order, }
              best_worth = worth
            }
          }
        }
      }
      best
    }
  }
}
