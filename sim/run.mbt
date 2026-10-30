///|
/// A check-in that cannot move arrival by at least this much, by any choice
/// of post, offers no decision about arrival.
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
  craft : @core.Craft
  cadence : Cadence
  joins_at : Int64
} derive(Debug, Eq)

///|
pub fn Actor::is_player(self : Actor) -> Bool {
  self.cadence is Every(_)
}

///|
/// The watch a player stands at each check-in: as long as the shortest
/// absence they expect, in whole hours. NPCs stand none, since they change
/// post at every boundary.
fn Actor::watch(self : Actor) -> Int64 {
  match self.cadence {
    Reactive => 0L
    Every(every~, jitter~) => {
      let hours = ((every - jitter) / @core.HOUR).max(1L)
      hours * @core.HOUR
    }
  }
}

///|
pub(all) struct Scenario {
  name : String
  ship : @ships.Profile
  route : @ships.Route
  /// Hull at departure, in `@core.HULL_FULL` units.
  hull : Int64
  /// The cruise of a single crossing, in thousandths of the γ cap. A voyage
  /// takes the temperament's cruise for each leg instead.
  cruise : Int64
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
  actor : String
  from : @core.Post?
  to : @core.Post
  watch : Int64
  /// Forecast arrival before and after.
  before : Int64
  after : Int64
  /// How far the best and worst choice of post would move arrival apart.
  leverage : Int64
  /// Choices of post, or of the other craft, that no other choice beats on
  /// arrival, hull, works, regard and refits together.
  undominated : Int32
  /// Things that happened since this crew member last checked in.
  news : Int32
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
  /// Player check-ins with at least two undominated choices.
  live_checkins : Int32
  /// Player check-ins that came back to something new.
  newsy_checkins : Int32
  /// The longest a player went between check-ins that offered a decision.
  longest_dead : Int64
  /// The arrived crossing, ready to dock.
  last : @core.Crossing
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
/// What a returning crew member would be told about: phase changes,
/// demands opening or closing, refits landing, their own watches stood and
/// works finished.
fn news(a : @core.Crossing, b : @core.Crossing, crew : String) -> Int32 {
  let mut n = 0
  if a.phase != b.phase {
    n += 1
  }
  for i, d in b.demands {
    if a.demands.get(i).map(x => x.status) != Some(d.status) {
      n += 1
    }
  }
  if refit_units(b.fit) / (100L * @core.HOUR * @core.CRAFT_UNIT) !=
    refit_units(a.fit) / (100L * @core.HOUR * @core.CRAFT_UNIT) {
    n += 1
  }
  match (a.tallies.get(crew), b.tallies.get(crew)) {
    (Some(x), Some(y)) => {
      if y.watches_stood > x.watches_stood {
        n += 1
      }
      if y.work / @core.WORK_SIZE > x.work / @core.WORK_SIZE {
        n += 1
      }
    }
    _ => ()
  }
  n
}

///|
/// The crew id of the actor at `i`, counting from zero.
pub fn actor_id(i : Int32) -> String {
  "crew \{i + 1}"
}

///|
/// The scenario's actor with crew id `crew`, if it is not a recruit.
pub fn Scenario::actor_of(self : Scenario, crew : String) -> Actor? {
  for i, a in self.actors {
    if actor_id(i) == crew {
      return Some(a)
    }
  }
  None
}

///|
/// The scenario's actors, with the ship's recruits added as steady NPCs.
pub fn Scenario::crew(self : Scenario, ship : @core.Ship) -> Array[Actor] {
  self.actors +
  Array::makei(ship.recruits.to_int(), i => {
    name: "recruit \{i + 1}",
    policy: Steady,
    craft: Artist,
    cadence: Reactive,
    joins_at: 0L,
  })
}

///|
fn id_of(i : Int32, actors : Int32) -> String {
  if i < actors {
    actor_id(i)
  } else {
    "recruit \{i - actors + 1}"
  }
}

///|
/// The ship this scenario departs with.
pub fn Scenario::departing(self : Scenario, seed : Int64) -> @core.Ship {
  { ..self.ship.ship(seed~), hull: self.hull, cruise: self.cruise, }
}

///|
pub fn Scenario::run(self : Scenario, seed : Int64) -> Run {
  self.fly(self.departing(seed), seed)
}

///|
/// Fly one crossing from `ship`. Time jumps from one instant of interest to
/// the next: a check-in, a join, or a boundary where a rate changes on its
/// own. The ship acts at every instant.
pub fn Scenario::fly(self : Scenario, ship : @core.Ship, seed : Int64) -> Run {
  let plan = self.route.plan_with(coils=ship.fit.coils, cruise=ship.cruise)
  let actors = self.crew(ship)
  let temperament = self.ship.temperament
  let mut c = @core.Crossing::new(plan, ship)
  let next = actors.map(a => a.joins_at)
  let rounds = Array::make(actors.length(), 0)
  let last_live = actors.map(a => a.joins_at)
  let seen = actors.map(_ => c)
  let mut longest_dead = 0L
  let samples = [sample(c)]
  let decisions = []
  let mut min_hull = c.hull
  let mut drive_ticks = 0L
  let mut hull_ticks = 0L
  let mut craft_ticks = 0L
  let mut checkins = 0
  let mut dead = 0
  let mut live = 0
  let mut newsy = 0
  let mut first = true
  let mut spoke : @core.Moment? = None
  let apply = (c : @core.Crossing, e : @core.CrossingEvent) => {
    c.apply(e) catch {
      _ => c
    }
  }
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
      let crew = id_of(i, self.actors.length())
      let joined = c.t >= actor.joins_at
      let due = next[i] == c.t ||
        (actor.cadence is Reactive && joined && at_boundary)
      guard due && joined else { continue }
      if !c.hands.contains(crew) {
        c = apply(
          apply(c, Posted(crew~, post=Craft)),
          Crafted(crew~, craft=actor.craft),
        )
      }
      if c.hands.get(crew) is Some({ post: Craft, banked, .. }) && banked > 0L {
        c = apply(c, Made(crew~))
      }
      let watch = actor.watch()
      let roll = draw(seed, i, rounds[i], 1)
      let options = posts.map(p => {
        prospect(try_option(c, crew, p, watch, order=handover(c)), crew)
      })
      let other : @core.Craft = if actor.craft == Artist {
        Engineer
      } else {
        Artist
      }
      let switched = apply(c, Crafted(crew~, craft=other))
      options.push(
        prospect(
          try_option(switched, crew, Craft, watch, order=handover(c)),
          crew,
        ),
      )
      let lev = options.fold(init=0L, (m, o) => m.max(o.arrival)) -
        options.fold(init=@math.MAX_TICKS, (m, o) => m.min(o.arrival))
      let before = c.forecast().unwrap_or(@math.MAX_TICKS)
      let from = c.hands.get(crew).map(h => h.post)
      let choice = actor.policy.decide(c, crew, watch, roll)
      let fresh = news(seen[i], c, crew)
      c = apply(c, Posted(crew~, post=choice.post))
      let on_watch = c.hands
        .get(crew)
        .map(h => h.watch is Some(_))
        .unwrap_or(false)
      if choice.watch > 0L && !on_watch {
        c = apply(c, Watched(crew~, ticks=choice.watch))
      }
      if c.hands.get(crew).map(h => h.order) != Some(choice.order) {
        c = apply(c, Ordered(crew~, order=choice.order))
      }
      seen[i] = c
      let after = c.forecast().unwrap_or(@math.MAX_TICKS)
      let open = undominated(options)
      decisions.push({
        t: c.t,
        actor: crew,
        from,
        to: choice.post,
        watch: choice.watch,
        before,
        after,
        leverage: lev,
        undominated: open,
        news: fresh,
      })
      rounds[i] += 1
      match actor.cadence {
        Reactive => next[i] = @math.MAX_TICKS
        Every(every~, jitter~) => {
          checkins += 1
          if fresh > 0 {
            newsy += 1
          }
          if open >= 2 {
            live += 1
          }
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
    let moment = c.moment()
    for act in temperament.turn(c, spoke) {
      match act {
        Refit(refit) => c = apply(c, Refitting(refit~))
        Ask(ask) => {
          spoke = Some(moment)
          if ask != c.ask {
            c = apply(c, Asked(post=ask))
          }
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
    live_checkins: live,
    newsy_checkins: newsy,
    longest_dead,
    last: c,
  }
}

///|
/// One crossing of a voyage, and the ship that left port after it.
pub(all) struct Leg {
  distance_ly : Double
  run : Run
  docked : @core.Ship
  /// The promotions made at arrival, before docking, as (crew, new rank).
  promotions : Array[(String, Int64)]
} derive(Debug, Eq)

///|
/// Fly `distances` one after another, docking between them, so refits,
/// recruits, hull and ranks carry from each crossing into the next.
pub fn Scenario::voyage(
  self : Scenario,
  distances : Array[Double],
  seed : Int64,
) -> Array[Leg] {
  let legs = []
  let mut ship = self.departing(seed)
  for d in distances {
    let s = { ..self, route: { ..self.route, distance_ly: d, }, }
    ship = {
      ..ship,
      cruise: self.ship.temperament.cruise(ship, distance_ly=d),
    }
    let run = s.fly(ship, seed + ship.crossings * 7919L)
    let promoted = @ships.promotions(run.last, officer=crew => {
      self.actor_of(crew).map(a => a.is_player()).unwrap_or(false)
    })
    let mut arrived = run.last
    for pair in promoted {
      arrived = arrived.apply(Promoted(crew=pair.0, rank=pair.1)) catch {
        err => abort("promotion: \{err.to_json().stringify()}")
      }
    }
    ship = arrived.dock().unwrap()
    legs.push({ distance_ly: d, run, docked: ship, promotions: promoted, })
  }
  legs
}
