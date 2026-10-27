///|
/// A check-in that cannot move arrival by at least this much, by any choice
/// of post, offers no decision worth the name.
pub const DEAD_LEVERAGE : Int64 = 300L

///|
pub(all) enum Cadence {
  /// Checks in on joining and whenever a rate changes on its own: an NPC.
  Reactive
  /// A player: checks in about every `every` ticks, give or take `jitter`.
  Every(every~ : Int64, jitter~ : Int64)
} derive(Debug, Eq)

///|
pub(all) struct Actor {
  name : String
  policy : Policy
  cadence : Cadence
  joins_at : Int64
} derive(Debug, Eq)

///|
pub fn Actor::is_player(self : Actor) -> Bool {
  self.cadence is Every(_)
}

///|
pub(all) struct Scenario {
  name : String
  route : Route
  /// Hull at departure, in `@core.HULL_FULL` units.
  hull : Int64
  actors : Array[Actor]
} derive(Debug, Eq)

///|
/// The ship at one instant, after that instant's decisions.
pub(all) struct Sample {
  t : Int64
  phase : @core.Phase
  eta : Int64
  hull : Int64
  setting : Int64
  drive : Int64
  mending : Int64
  crafting : Int64
  forecast : Int64
} derive(Debug, Eq)

///|
/// One check-in, whether or not it changed anything.
pub(all) struct Decision {
  t : Int64
  actor : Int32
  from : @core.Post?
  to : @core.Post
  /// Forecast arrival before and after.
  before : Int64
  after : Int64
  /// How far the best and worst choice of post would move arrival apart.
  leverage : Int64
} derive(Debug, Eq)

///|
pub(all) struct Run {
  seed : Int64
  plan : @core.Plan
  samples : Array[Sample]
  decisions : Array[Decision]
  arrived_at : Int64
  min_hull : Int64
  end_hull : Int64
  /// Crew-ticks spent on the drive, the hull and crafts.
  drive_ticks : Int64
  hull_ticks : Int64
  craft_ticks : Int64
  /// Player check-ins, and those with less than `DEAD_LEVERAGE`.
  checkins : Int32
  dead_checkins : Int32
  /// The longest a player went between check-ins that offered a decision.
  longest_dead : Int64
} derive(Debug, Eq)

///|
fn sample(c : @core.Crossing) -> Sample {
  {
    t: c.t,
    phase: c.phase,
    eta: c.eta(),
    hull: c.hull,
    setting: c.setting(),
    drive: c.count(Drive),
    mending: c.count(Hull),
    crafting: c.count(Craft),
    forecast: c.forecast().unwrap_or(@math.MAX_TICKS),
  }
}

///|
fn leverage(c : @core.Crossing, crew : Int32) -> Int64 {
  let ats = posts.map(post => forecast_with(c, crew, post))
  let mut lo = ats[0]
  let mut hi = ats[0]
  for at in ats {
    lo = lo.min(at)
    hi = hi.max(at)
  }
  hi - lo
}

///|
/// Fly one crossing. Time jumps from one instant of interest to the next: a
/// check-in, a join, or a boundary where a rate changes on its own.
pub fn Scenario::run(self : Scenario, seed : Int64) -> Run {
  let plan = self.route.plan()
  let actors = self.actors
  let mut c = @core.Crossing::new(plan, hull=self.hull)
  let next = actors.map(a => a.joins_at)
  let rounds = Array::make(actors.length(), 0)
  let last_live = actors.map(a => a.joins_at)
  let mut longest_dead = 0L
  let samples = [sample(c)]
  let decisions = []
  let mut min_hull = c.hull
  let mut drive_ticks = 0L
  let mut hull_ticks = 0L
  let mut craft_ticks = 0L
  let mut checkins = 0
  let mut dead = 0
  let mut first = true
  for _ in 0..<1_000_000 {
    guard c.arrived_at is None else { break }
    let boundary = c.t + c.next_boundary()
    let mut now = boundary
    for at in next {
      now = now.min(at)
    }
    if now > c.t {
      let dt = now - c.t
      drive_ticks += c.count(Drive) * dt
      hull_ticks += c.count(Hull) * dt
      craft_ticks += c.count(Craft) * dt
      c = c.apply(Elapsed(ticks=dt)) catch { _ => panic() }
      min_hull = min_hull.min(c.hull)
    }
    guard c.arrived_at is None else { break }
    let at_boundary = first || now == boundary
    first = false
    for i, actor in actors {
      let joined = c.t >= actor.joins_at
      let due = next[i] == c.t ||
        (actor.cadence is Reactive && joined && at_boundary)
      guard due && joined else { continue }
      let roll = draw(seed, i, rounds[i], 1)
      let lev = leverage(c, i)
      let before = c.forecast().unwrap_or(@math.MAX_TICKS)
      let from = c.posts.get(i)
      let to = actor.policy.decide(c, i, roll)
      c = c.apply(Posted(crew=i, post=to)) catch { _ => panic() }
      let after = c.forecast().unwrap_or(@math.MAX_TICKS)
      decisions.push({
        t: c.t,
        actor: i,
        from,
        to,
        before,
        after,
        leverage: lev,
      })
      rounds[i] += 1
      match actor.cadence {
        Reactive => next[i] = @math.MAX_TICKS
        Every(every~, jitter~) => {
          checkins += 1
          if lev < DEAD_LEVERAGE {
            dead += 1
          } else {
            longest_dead = longest_dead.max(c.t - last_live[i])
            last_live[i] = c.t
          }
          let offset = draw_below(seed, i, rounds[i], 2, 2L * jitter + 1L) -
            jitter
          next[i] = c.t + (every + offset).max(1L)
        }
      }
    }
    samples.push(sample(c))
  }
  let arrived_at = c.arrived_at.unwrap_or(c.t)
  for i, actor in actors {
    if actor.is_player() && actor.joins_at < arrived_at {
      longest_dead = longest_dead.max(arrived_at - last_live[i])
    }
  }
  samples.push(sample(c))
  {
    seed,
    plan,
    samples,
    decisions,
    arrived_at,
    min_hull,
    end_hull: c.hull,
    drive_ticks,
    hull_ticks,
    craft_ticks,
    checkins,
    dead_checkins: dead,
    longest_dead,
  }
}
