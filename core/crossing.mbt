///|
/// A full hull. Hull is held in billionths so wear at the lowest setting
/// still moves it by whole units.
pub const HULL_FULL : Int64 = 1_000_000_000L

///|
/// Most rate boundaries one forecast steps through before giving up.
pub const MAX_BOUNDARIES : Int32 = 4096

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
pub(all) struct Watch {
  from : Int64
  until : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Order {
  phase : Phase
  post : Post
} derive(Debug, Eq, ToJson, FromJson)

///|
/// One crew member aboard.
pub(all) struct Hand {
  post : Post
  craft : Craft
  /// Rank aboard: from the ship's records at joining, raised by a promotion
  /// at arrival. Gates nothing.
  rank : Int64
  watch : Watch?
  /// A standing order: the post to take when a phase begins. A watch in
  /// progress carries over to the new post.
  order : Order?
  /// Work units accrued at the craft post and not yet made. See
  /// `CrossingEvent::Made`.
  banked : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Hand::quarters(self : Hand) -> Int64 {
  if self.watch is Some(_) {
    WATCH_HAND
  } else {
    HAND
  }
}

///|
/// What one crew member did this crossing. Kept after they leave.
pub(all) struct Tally {
  /// Quarter-hand-ticks on each post.
  drive : Int64
  hull : Int64
  craft : Int64
  regard : Int64
  /// Work units toward works, for artists.
  work : Int64
  watches_stood : Int64
  watches_broken : Int64
  /// Ticks aboard holding a post, away or not.
  served : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
let no_tally : Tally = {
  drive: 0,
  hull: 0,
  craft: 0,
  regard: 0,
  work: 0,
  watches_stood: 0,
  watches_broken: 0,
  served: 0,
}

///|
pub(all) struct Crossing {
  plan : Plan
  ship : Ship
  /// Ticks since departure.
  t : Int64
  phase : Phase
  /// What remains of the current phase's stock: rapidity to gain in the burn,
  /// distance in the coast, rapidity to shed in the approach.
  left : Int64
  hull : Int64
  /// Hull band, which sets the drive's cap. See `rebanded`.
  band : Int64
  /// The ship's fit as of now; refits land here as they finish.
  fit : Fit
  hands : Map[String, Hand]
  tallies : Map[String, Tally]
  demands : Array[Demand]
  /// The post the ship is asking for, if any.
  ask : Post?
  arrived_at : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum CrossingEvent {
  Elapsed(ticks~ : Int64)
  /// Takes a post, joining the crew if not aboard. Breaks a watch on another
  /// post.
  Posted(crew~ : String, post~ : Post)
  Left(crew~ : String)
  Crafted(crew~ : String, craft~ : Craft)
  /// Stands a watch on the current post for `ticks`.
  Watched(crew~ : String, ticks~ : Int64)
  /// Takes `post` when `phase` begins, or cancels the standing order.
  Ordered(crew~ : String, order~ : Order?)
  /// What the engineers build next.
  Refitting(refit~ : Refit?)
  /// The ship asks for hands on a post, or stops asking.
  Asked(post~ : Post?)
  /// The ship promotes `crew` to `rank`, one step, once arrived.
  Promoted(crew~ : String, rank~ : Int64)
  /// `crew` makes the work they have banked, at 100 to 150 percent of it,
  /// into their current craft.
  Made(crew~ : String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror CrossingRejected {
  BadTicks(ticks~ : Int64)
  NotAboard(crew~ : String)
  BadWatch(ticks~ : Int64)
  OnWatch(crew~ : String)
  Unbuildable(refit~ : Refit)
  /// A promotion is one step up, to at most `COMMANDER`.
  BadPromotion(crew~ : String, rank~ : Int64)
  /// Orders are for a phase still to come.
  BadOrder(phase~ : Phase)
  /// There is no banked work to make.
  NothingBanked(crew~ : String)
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Depart with `ship`'s hull and fit. The crossing's demands are fixed here.
pub fn Crossing::new(plan : Plan, ship : Ship) -> Crossing {
  {
    plan,
    ship,
    t: 0,
    phase: Burn,
    left: plan.burn,
    hull: ship.hull,
    band: band_of(ship.hull),
    fit: ship.fit,
    hands: {},
    tallies: {},
    demands: demands_for(plan, ship.seed, ship.crossings),
    ask: None,
    arrived_at: None,
  }.settle()
}

///|
/// Ticks `crew` has served aboard this ship: every crossing docked, and
/// this one so far.
pub fn Crossing::served(self : Crossing, crew : String) -> Int64 {
  self.ship.records.get(crew).map(r => r.served).unwrap_or(0L) +
  self.tallies.get(crew).map(t => t.served).unwrap_or(0L)
}

///|
/// Crew members on `post`.
pub fn Crossing::count(self : Crossing, post : Post) -> Int64 {
  self.hands.values().filter(h => h.post == post).count().to_int64()
}

///|
/// Quarter-hands on `post`, counting a quarter more for each on watch.
pub fn Crossing::quarters(self : Crossing, post : Post) -> Int64 {
  self.hands
  .values()
  .fold(init=0L, (n, h) => if h.post == post { n + h.quarters() } else { n })
}

///|
/// Crafters of `craft` working together now.
fn Crossing::crafting(self : Crossing, craft : Craft) -> Int64 {
  self.hands
  .values()
  .filter(h => h.post == Craft && h.craft == craft)
  .count()
  .to_int64()
}

///|
/// Work units per tick for one crafter: a quarter more for each other
/// crafter of the same craft at work, up to four.
fn Crossing::craft_rate(self : Crossing, hand : Hand) -> Int64 {
  guard hand.post == Craft else { 0L }
  let together = (self.crafting(hand.craft) - 1L).min(HAND)
  hand.quarters() * (HAND + together)
}

///|
/// How far above a band's lower edge the hull must climb before the band
/// is restored. Without the gap a ship mending at an edge drops a band,
/// wears less at the lower cap, climbs back, and repeats every tick.
pub const BAND_MARGIN : Int64 = 50_000_000L

///|
/// The band a hull falls into with no history: 0 below a quarter, 3 from
/// three quarters up.
pub fn band_of(hull : Int64) -> Int64 {
  (hull * 4L / HULL_FULL).min(3L)
}

///|
/// The hull at which `band` rises to the next.
fn rise_at(band : Int64) -> Int64 {
  (band + 1L) * HULL_FULL / 4L + BAND_MARGIN
}

///|
/// `band` after the hull moved to `hull`: it falls as soon as the hull is
/// below its edge, and rises only past `rise_at`.
fn rebanded(band : Int64, hull : Int64) -> Int64 {
  if hull < band * HULL_FULL / 4L {
    band_of(hull)
  } else {
    for b = band {
      if b < 3L && hull >= rise_at(b) {
        continue b + 1L
      }
      break b
    }
  }
}

///|
/// The highest setting the hull allows: 0.512, 0.675, 0.837 or full.
pub fn Crossing::cap(self : Crossing) -> Int64 {
  @math.SETTING_FLOOR +
  (@math.SETTING_FULL - @math.SETTING_FLOOR) * (self.band + 1L) / 4L
}

///|
pub fn Crossing::setting(self : Crossing) -> Int64 {
  let drive = self.quarters(Drive).min(4096L)
  @math.setting(drive, self.fit.needed * HAND, self.cap())
}

///|
pub fn Crossing::firing(self : Crossing) -> Bool {
  self.phase is (Burn | Approach)
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
  let repair = self.fit.repair * self.quarters(Hull) / HAND
  match self.phase {
    Burn | Approach => {
      let s = self.setting()
      let wear = @math.rate(@math.rate(self.fit.wear, s), s)
      (@math.rate(self.plan.eta_rate, s), repair - wear)
    }
    Coast => (self.plan.coast_rate, repair)
    Arrived => (0, 0)
  }
}

///|
/// Whether a post's hours do anything now. Regard counts only these: the
/// drive while it fires, the hull while it is short of full or a breach is
/// open, and any craft.
fn Crossing::useful(self : Crossing, post : Post) -> Bool {
  match post {
    Drive => self.firing()
    Hull => self.hull < HULL_FULL || self.open_on(Hull)
    Craft => true
  }
}

///|
fn Crossing::open_on(self : Crossing, post : Post) -> Bool {
  self.demands.iter().any(d => d.status == Open && d.hazard.post() == post)
}

///|
/// Regard per tick for one hand. Doubled for the post the ship asks for,
/// and again for the post an open demand needs.
fn Crossing::regard_rate(self : Crossing, hand : Hand) -> Int64 {
  guard self.useful(hand.post) && self.phase != Arrived else { 0L }
  let asked = if self.ask == Some(hand.post) { 2L } else { 1L }
  let needed = if self.open_on(hand.post) { 2L } else { 1L }
  self.ship.values.weight(hand.post) * hand.quarters() * asked * needed
}

///|
/// Ticks until a rate next changes on its own: the phase ends, the hull
/// crosses into another band or fills, a demand opens or is met, a watch
/// ends, or a refit is finished. Rates are constant until then, so the
/// state between boundaries is linear.
pub fn Crossing::next_boundary(self : Crossing) -> Int64 {
  guard self.phase != Arrived else { @math.MAX_TICKS }
  let (rate, net) = self.rates()
  let mut next = @math.ticks_to_empty(self.left, rate)
  let band = self.band
  if net < 0L && self.hull == HULL_FULL {
    // The hull post becomes useful, and earns regard, a tick from now.
    next = 1L
  } else if net < 0L && band > 0L && self.hull > 0L {
    next = next.min(
      @math.ticks_to_empty(self.hull - band * HULL_FULL / 4L + 1L, -net),
    )
  } else if net > 0L && self.hull < HULL_FULL {
    let edge = if band < 3L { rise_at(band) } else { HULL_FULL }
    next = next.min(@math.ticks_to_empty(edge - self.hull, net))
  }
  for d in self.demands {
    if d.status == Waiting && d.phase == self.phase && self.left > d.opens_at {
      next = next.min(@math.ticks_to_empty(self.left - d.opens_at, rate))
    } else if d.status == Open {
      let q = self.quarters(d.hazard.post())
      if q > 0L {
        next = next.min(@math.ticks_to_empty(d.need - d.done, q))
      }
    }
  }
  for h in self.hands.values() {
    if h.watch is Some(w) {
      next = next.min(w.until - self.t)
    }
  }
  next.min(@math.MAX_TICKS)
}

///|
/// Linear progress over `step` ticks, which must not pass a boundary.
fn Crossing::flow(self : Crossing, step : Int64) -> Crossing {
  let (rate, net) = self.rates()
  let tallies = self.tallies.copy()
  let hands = self.hands.copy()
  for crew, h in self.hands {
    let q = h.quarters() * step
    let t = tallies.get(crew).unwrap_or(no_tally)
    let t = match h.post {
      Drive => { ..t, drive: t.drive + q, }
      Hull => { ..t, hull: t.hull + q, }
      Craft => { ..t, craft: t.craft + q, }
    }
    tallies[crew] = {
      ..t,
      regard: t.regard + self.regard_rate(h) * step,
      served: t.served + step,
    }
    if h.post == Craft {
      hands[crew] = { ..h, banked: h.banked + self.craft_rate(h) * step, }
    }
  }
  let demands = self.demands.map(d => {
    guard d.status == Open else { d }
    { ..d, done: d.done + self.quarters(d.hazard.post()) * step, }
  })
  {
    ..self,
    t: self.t + step,
    left: @math.deplete(self.left, rate, step),
    hull: @math.settle(self.hull, net, step, HULL_FULL),
    hands,
    tallies,
    demands,
  }
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
fn Crossing::lose_hull(self : Crossing, amount : Int64) -> Crossing {
  { ..self, hull: (self.hull - amount).max(0L), }
}

///|
/// Apply whatever is due at this instant: finished watches and refits, met
/// and missed demands, the phase change, and demands that open. Each pass
/// either changes something or stops, and each thing can happen only a
/// bounded number of times, so this ends.
fn Crossing::settle(self : Crossing) -> Crossing {
  let mut c = self
  let mut changed = false
  let band = rebanded(c.band, c.hull)
  if band != c.band {
    c = { ..c, band, }
    changed = true
  }
  // Arrival ends every watch, paid for the part stood. One begun after
  // arrival stood nothing and is dropped uncounted.
  let ends = (w : Watch) => w.until <= c.t || c.phase == Arrived
  if c.hands.values().any(h => h.watch is Some(w) && ends(w)) {
    let hands = c.hands.copy()
    let tallies = c.tallies.copy()
    for crew, h in c.hands {
      if h.watch is Some(w) && ends(w) {
        let stood = w.until.min(c.t) - w.from
        if stood > 0L {
          let t = tallies.get(crew).unwrap_or(no_tally)
          tallies[crew] = {
            ..t,
            regard: t.regard + stood * WATCH_BONUS,
            watches_stood: t.watches_stood + 1L,
          }
        }
        hands[crew] = { ..h, watch: None, }
      }
    }
    c = { ..c, hands, tallies, }
    changed = true
  }
  while c.fit.refit is Some(r) && c.fit.progress >= c.fit.cost(r) {
    c = { ..c, fit: c.fit.build(r), }
    changed = true
  }
  let due = (d : Demand) => {
    d.status == Open &&
    (d.done >= d.need || (c.left == 0L && d.phase == c.phase))
  }
  if c.demands.iter().any(due) {
    let mut loss = 0L
    let demands = c.demands.map(d => {
      guard due(d) else { d }
      if d.done >= d.need {
        { ..d, status: Met, }
      } else {
        loss += match d.hazard {
          Breach => BREACH_LOSS
          Flare => FLARE_LOSS
          Dust => DUST_LOSS
        }
        { ..d, status: Missed, }
      }
    })
    c = { ..c, demands, }.lose_hull(loss)
    changed = true
  }
  if c.left == 0L && c.phase != Arrived {
    c = c.next_phase()
    let phase = c.phase
    if c.hands.values().any(h => h.order is Some(o) && o.phase <= phase) {
      let hands = c.hands.copy()
      for crew, h in c.hands {
        if h.order is Some(o) && o.phase <= phase {
          let post = if o.phase == phase { o.post } else { h.post }
          hands[crew] = { ..h, post, order: None, }
        }
      }
      c = { ..c, hands, }
    }
    changed = true
  }
  let opens = (d : Demand) => {
    d.status == Waiting &&
    (d.phase < c.phase || (d.phase == c.phase && c.left <= d.opens_at))
  }
  if c.demands.iter().any(opens) {
    let demands = c.demands.map(d => {
      guard opens(d) else { d }
      { ..d, status: if d.phase == c.phase { Open } else { Missed }, }
    })
    c = { ..c, demands, }
    changed = true
  }
  if changed {
    c.settle()
  } else {
    c
  }
}

///|
/// Regard per tick of a watch, paid when it is stood to its end.
pub const WATCH_BONUS : Int64 = 4L

///|
/// Regard per tick of a watch already stood, lost by breaking it.
pub const WATCH_PENALTY : Int64 = 8L

///|
/// Advance by `ticks`, stepping from boundary to boundary.
fn Crossing::advance(self : Crossing, ticks : Int64) -> Crossing {
  for c = self, remaining = ticks {
    if remaining == 0L {
      break c
    }
    if c.phase == Arrived {
      break { ..c, t: c.t + remaining, }
    }
    let step = remaining.min(c.next_boundary())
    continue c.flow(step).settle(), remaining - step
  }
}

///|
fn Crossing::hand(
  self : Crossing,
  crew : String,
) -> Hand raise CrossingRejected {
  guard self.hands.get(crew) is Some(h) else { raise NotAboard(crew~) }
  h
}

///|
/// Ends `crew`'s watch early: the ship remembers.
fn Crossing::break_watch(self : Crossing, crew : String, h : Hand) -> Crossing {
  guard h.watch is Some(w) else { self }
  let tallies = self.tallies.copy()
  let t = tallies.get(crew).unwrap_or(no_tally)
  let lost = ((self.t - w.from) * WATCH_PENALTY).min(t.regard)
  tallies[crew] = {
    ..t,
    regard: t.regard - lost,
    watches_broken: t.watches_broken + 1L,
  }
  { ..self, tallies, }
}

///|
fn Crossing::with_hand(self : Crossing, crew : String, h : Hand) -> Crossing {
  let hands = self.hands.copy()
  hands[crew] = h
  let tallies = if self.tallies.contains(crew) {
    self.tallies
  } else {
    let tallies = self.tallies.copy()
    tallies[crew] = no_tally
    tallies
  }
  { ..self, hands, tallies, }
}

///|
/// Lowest and highest percent of banked work a making can yield.
pub const MAKE_MIN : Int64 = 100L

///|
pub const MAKE_MAX : Int64 = 150L

///|
/// The percent of their bank a crew member gets for making at tick `t`:
/// `MAKE_MIN` to `MAKE_MAX`, fixed by the ship's `seed`, the crew id and `t`.
/// An FNV-1a hash over `Int64` words and the id's UTF-16 code units, so js
/// and native agree.
pub fn craft_percent(seed : Int64, crew : String, t : Int64) -> Int64 {
  let prime = 0x100000001b3L
  let mut h = -3750763034362895579L
  let mix = (word : Int64) => {
    for i in 0..<8 {
      h = (h ^ ((word >> (i * 8)) & 0xffL)) * prime
    }
  }
  mix(seed)
  mix(t)
  for i in 0..<crew.length() {
    h = (h ^ crew.code_unit_at(i).to_int64()) * prime
  }
  h = h ^ (h >> 32)
  h = h * prime
  h = h ^ (h >> 29)
  MAKE_MIN + (h & 0x7fffffffL) % (MAKE_MAX - MAKE_MIN + 1L)
}

///|
/// Make `crew`'s banked work at `percent` of it, into their current craft: an
/// artist's work, or the engineers' refit progress. Does nothing if nothing
/// is banked. Not settled; callers settle or go on to.
fn Crossing::make(self : Crossing, crew : String, percent : Int64) -> Crossing {
  guard self.hands.get(crew) is Some(h) && h.banked > 0L else { self }
  let units = h.banked * percent / 100L
  let hands = self.hands.copy()
  hands[crew] = { ..h, banked: 0, }
  match h.craft {
    Artist => {
      let tallies = self.tallies.copy()
      let t = tallies.get(crew).unwrap_or(no_tally)
      tallies[crew] = { ..t, work: t.work + units, }
      { ..self, hands, tallies, }
    }
    Engineer =>
      {
        ..self,
        hands,
        fit: { ..self.fit, progress: self.fit.progress + units, },
      }
  }
}

///|
pub fn Crossing::apply(
  self : Crossing,
  event : CrossingEvent,
) -> Crossing raise CrossingRejected {
  let c = match event {
    Elapsed(ticks~) => {
      guard ticks > 0L && ticks <= @math.MAX_TICKS else {
        raise BadTicks(ticks~)
      }
      self.advance(ticks)
    }
    Posted(crew~, post~) =>
      match self.hands.get(crew) {
        Some(h) if h.post == post => self
        Some(h) =>
          self.break_watch(crew, h).with_hand(crew, { ..h, post, watch: None, })
        None =>
          self.with_hand(crew, {
            post,
            craft: Artist,
            rank: self.ship.rank(crew),
            watch: None,
            order: None,
            banked: 0,
          })
      }
    Left(crew~) => {
      let h = self.hand(crew)
      let c = self.make(crew, 100L).break_watch(crew, h)
      let hands = c.hands.copy()
      hands.remove(crew)
      { ..c, hands, }
    }
    Crafted(crew~, craft~) => {
      let h = self.hand(crew)
      self.with_hand(crew, { ..h, craft, })
    }
    Watched(crew~, ticks~) => {
      let h = self.hand(crew)
      guard h.watch is None else { raise OnWatch(crew~) }
      guard ticks >= HOUR else { raise BadWatch(ticks~) }
      self.with_hand(crew, {
        ..h,
        watch: Some({ from: self.t, until: self.t + ticks, }),
      })
    }
    Ordered(crew~, order~) => {
      let h = self.hand(crew)
      if order is Some(o) && (o.phase <= self.phase || o.phase == Arrived) {
        raise BadOrder(phase=o.phase)
      }
      self.with_hand(crew, { ..h, order, })
    }
    Refitting(refit~) => {
      if refit is Some(r) && !self.fit.can_refit(r) {
        raise Unbuildable(refit=r)
      }
      { ..self, fit: { ..self.fit, refit, }, }
    }
    Made(crew~) => {
      let h = self.hand(crew)
      guard h.banked > 0L else { raise NothingBanked(crew~) }
      self.make(crew, craft_percent(self.ship.seed, crew, self.t))
    }
    Asked(post~) => { ..self, ask: post, }
    Promoted(crew~, rank~) => {
      let h = self.hand(crew)
      guard rank == h.rank + 1L && rank <= COMMANDER else {
        raise BadPromotion(crew~, rank~)
      }
      self.with_hand(crew, { ..h, rank, })
    }
  }
  c.settle()
}

///|
/// What the ship notices happening: the phase, each demand's status and the
/// hull band. Crew moving is not a moment.
pub(all) struct Moment {
  phase : Phase
  demands : Array[Status]
  band : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Crossing::moment(self : Crossing) -> Moment {
  {
    phase: self.phase,
    demands: self.demands.map(d => d.status),
    band: self.band,
  }
}

///|
/// Where the crossing ends if no one does anything more: the arrived
/// crossing, or `None` if it would take more than `MAX_BOUNDARIES` steps.
pub fn Crossing::project(self : Crossing) -> Crossing? {
  let mut c = self
  for _ in 0..<MAX_BOUNDARIES {
    if c.arrived_at is Some(_) {
      return Some(c)
    }
    c = c.advance(c.next_boundary())
  }
  None
}

///|
/// When the ship arrives if no one changes post, in ticks since departure.
pub fn Crossing::forecast(self : Crossing) -> Int64? {
  if self.arrived_at is Some(at) {
    return Some(at)
  }
  self.project().map(c => c.arrived_at.unwrap())
}

///|
/// When the current phase ends if no one changes post, in ticks since
/// departure: `None` once arrived, or if it would take more than
/// `MAX_BOUNDARIES` steps.
pub fn Crossing::phase_ends(self : Crossing) -> Int64? {
  guard self.phase != Arrived else { None }
  let mut c = self
  for _ in 0..<MAX_BOUNDARIES {
    if c.phase != self.phase {
      return Some(c.t)
    }
    c = c.advance(c.next_boundary())
  }
  None
}

///|
/// Settle an arrived crossing into the ship that leaves port: regard and
/// works go to each crew member's record, works bring recruits, the yard
/// repairs the hull, and refits stay fitted.
pub fn Crossing::dock(self : Crossing) -> Ship? {
  guard self.phase == Arrived else { None }
  let mut c = self
  for crew, _ in self.hands {
    c = c.make(crew, 100L)
  }
  let self = c.settle()
  let ship = self.ship
  let records = ship.records.copy()
  let mut delivered = 0L
  for crew, t in self.tallies {
    let r = records
      .get(crew)
      .unwrap_or({ regard: 0, works: 0, carry: 0, rank: None, served: 0, })
    let rank = match self.hands.get(crew) {
      Some(h) => h.rank
      None => ship.rank(crew)
    }
    let units = r.carry + t.work
    delivered += units / WORK_SIZE
    records[crew] = {
      regard: r.regard + t.regard,
      works: r.works + units / WORK_SIZE,
      carry: units % WORK_SIZE,
      rank: Some(rank),
      served: r.served + t.served,
    }
  }
  let toward = ship.toward_recruit + delivered
  let recruits = (ship.recruits + toward / WORKS_PER_RECRUIT).min(MAX_RECRUITS)
  Some({
    ..ship,
    fit: self.fit,
    hull: (self.hull + PORT_REPAIR).min(HULL_FULL),
    records,
    recruits,
    toward_recruit: toward % WORKS_PER_RECRUIT,
    crossings: ship.crossings + 1L,
  })
}
