///|
/// A full hull. Hull is held in billionths so wear at the lowest setting
/// still moves it by whole units.
pub const HULL_FULL : Int64 = 1_000_000_000L

///|
/// What a crew member's hours go to. See `docs/gameplay.md`.
pub(all) enum Post {
  Drive
  Hull
  Craft
} derive(Debug, Eq, Compare, Hash, ToJson, FromJson)

///|
pub(all) enum Phase {
  Burn
  Coast
  Approach
  Arrived
} derive(Debug, Eq, Compare, ToJson, FromJson)

///|
/// One route for one ship, worked out offline from the closed-form
/// kinematics. Rapidity is in billionths and distance in billionths of a
/// light-year; one tick is one second aboard.
pub(all) struct Plan {
  /// Rapidity gained in the burn and shed in the approach.
  burn : Int64
  /// Distance run at the cap between them; zero if the ship never reaches it.
  coast : Int64
  /// Rapidity per tick at full burn.
  eta_rate : Int64
  /// Distance per tick at the cap.
  coast_rate : Int64
  /// Drive hands for full burn.
  drive_needed : Int64
  /// Hull lost per tick at full burn. Scales with the setting squared.
  wear : Int64
  /// Hull restored per tick by each hand on the hull.
  repair : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Ticks for the whole crossing at a fixed setting, phase by phase.
fn Plan::ticks_at(self : Plan, setting : Int64) -> Int64 {
  let burn = @math.ticks_to_empty(self.burn, @math.rate(self.eta_rate, setting))
  burn * 2L + @math.ticks_to_empty(self.coast, self.coast_rate)
}

///|
/// The soonest any crew can arrive: full burn throughout.
pub fn Plan::fastest(self : Plan) -> Int64 {
  self.ticks_at(@math.SETTING_FULL)
}

///|
/// The latest any crew can arrive: the floor throughout.
pub fn Plan::slowest(self : Plan) -> Int64 {
  self.ticks_at(@math.SETTING_FLOOR)
}

///|
pub(all) struct Crossing {
  plan : Plan
  /// Ticks since departure.
  t : Int64
  phase : Phase
  /// What remains of the current phase's stock: rapidity to gain in the burn,
  /// distance in the coast, rapidity to shed in the approach.
  left : Int64
  hull : Int64
  posts : Map[Int32, Post]
  arrived_at : Int64?
} derive(Debug, Eq)

///|
pub(all) enum CrossingEvent {
  Elapsed(ticks~ : Int64)
  /// Takes a post, joining the crew if not aboard.
  Posted(crew~ : Int32, post~ : Post)
  Left(crew~ : Int32)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror CrossingRejected {
  BadTicks(ticks~ : Int64)
  NotAboard(crew~ : Int32)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Crossing::new(plan : Plan, hull~ : Int64) -> Crossing {
  {
    plan,
    t: 0,
    phase: Burn,
    left: plan.burn,
    hull,
    posts: {},
    arrived_at: None,
  }
}

///|
pub fn Crossing::count(self : Crossing, post : Post) -> Int64 {
  self.posts.values().filter(p => p == post).count().to_int64()
}

///|
/// Hull band: 0 below a quarter, 3 from three quarters up.
pub fn Crossing::band(self : Crossing) -> Int64 {
  (self.hull * 4L / HULL_FULL).min(3L)
}

///|
/// The highest setting the hull allows: 0.512, 0.675, 0.837 or full.
pub fn Crossing::cap(self : Crossing) -> Int64 {
  @math.SETTING_FLOOR +
  (@math.SETTING_FULL - @math.SETTING_FLOOR) * (self.band() + 1L) / 4L
}

///|
pub fn Crossing::setting(self : Crossing) -> Int64 {
  let drive = self.count(Drive).min(64L)
  @math.setting(drive, self.plan.drive_needed, self.cap())
}

///|
/// Rapidity in billionths, for display.
pub fn Crossing::eta(self : Crossing) -> Int64 {
  match self.phase {
    Burn => self.plan.burn - self.left
    Coast => self.plan.burn
    Approach => self.left
    Arrived => 0
  }
}

///|
/// Per-tick rates now: the phase stock's, and the hull's (signed).
fn Crossing::rates(self : Crossing) -> (Int64, Int64) {
  let repair = self.plan.repair * self.count(Hull)
  match self.phase {
    Burn | Approach => {
      let s = self.setting()
      let wear = @math.rate(@math.rate(self.plan.wear, s), s)
      (@math.rate(self.plan.eta_rate, s), repair - wear)
    }
    Coast => (self.plan.coast_rate, repair)
    Arrived => (0, 0)
  }
}

///|
/// Ticks until a rate next changes on its own: the phase ends or the hull
/// crosses into another band. Rates are constant until then, so the state
/// between boundaries is linear.
pub fn Crossing::next_boundary(self : Crossing) -> Int64 {
  let (rate, net) = self.rates()
  guard self.phase != Arrived else { @math.MAX_TICKS }
  let phase_end = @math.ticks_to_empty(self.left, rate)
  let band = self.band()
  let band_edge = if net < 0L && band > 0L && self.hull > 0L {
    @math.ticks_to_empty(self.hull - band * HULL_FULL / 4L + 1L, -net)
  } else if net > 0L && band < 3L {
    @math.ticks_to_empty((band + 1L) * HULL_FULL / 4L - self.hull, net)
  } else {
    @math.MAX_TICKS
  }
  phase_end.min(band_edge)
}

///|
fn Crossing::next_phase(self : Crossing) -> Crossing {
  match self.phase {
    Burn if self.plan.coast > 0L =>
      { ..self, phase: Coast, left: self.plan.coast, }
    Burn | Coast => { ..self, phase: Approach, left: self.plan.burn, }
    Approach | Arrived =>
      {
        ..self,
        phase: Arrived,
        left: 0,
        arrived_at: Some(self.arrived_at.unwrap_or(self.t)),
      }
  }
}

///|
/// Advance by `ticks`, stepping from boundary to boundary. Each phase can
/// cross each hull band at most once, so the loop is short.
fn Crossing::advance(self : Crossing, ticks : Int64) -> Crossing {
  for c = self, remaining = ticks {
    if remaining == 0L {
      break c
    }
    if c.phase == Arrived {
      break { ..c, t: c.t + remaining, }
    }
    let (rate, net) = c.rates()
    let step = remaining.min(c.next_boundary())
    let c = {
      ..c,
      t: c.t + step,
      left: @math.deplete(c.left, rate, step),
      hull: @math.settle(c.hull, net, step, HULL_FULL),
    }
    let c = if c.left == 0L { c.next_phase() } else { c }
    continue c, remaining - step
  }
}

///|
pub fn Crossing::apply(
  self : Crossing,
  event : CrossingEvent,
) -> Crossing raise CrossingRejected {
  match event {
    Elapsed(ticks~) => {
      guard ticks > 0L && ticks <= @math.MAX_TICKS else {
        raise BadTicks(ticks~)
      }
      self.advance(ticks)
    }
    Posted(crew~, post~) => {
      let posts = self.posts.copy()
      posts[crew] = post
      { ..self, posts, }
    }
    Left(crew~) => {
      guard self.posts.contains(crew) else { raise NotAboard(crew~) }
      let posts = self.posts.copy()
      posts.remove(crew)
      { ..self, posts, }
    }
  }
}

///|
/// When the ship arrives if no one changes post, in ticks since departure.
/// `None` only if the plan cannot be flown, which `Plan` validation rules out.
pub fn Crossing::forecast(self : Crossing) -> Int64? {
  if self.arrived_at is Some(at) {
    return Some(at)
  }
  let mut c = self
  for _ in 0..<64 {
    c = c.advance(c.next_boundary())
    if c.arrived_at is Some(at) {
      return Some(at)
    }
  }
  None
}
