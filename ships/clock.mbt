///|
/// How long, in seconds, an arrived ship with a mind waits for it to choose
/// promotions before the clock promotes by script and docks.
pub const MIND_WAIT : Int64 = 300L

///|
/// When the crossing under way arrived, in Unix seconds, if it has.
pub fn arrived_at(state : @core.State) -> Int64? {
  guard state.crossing() is Some(c) && c.arrived_at is Some(ticks) else {
    return None
  }
  // A tick is a second, and `t` keeps counting after arrival.
  Some(state.at - (c.t - ticks))
}

///|
/// The ship `id` in the fleet's list, as it is in `state`.
pub fn listing(id : String, state : @core.State) -> @core.Listing {
  let whereabouts : @core.Whereabouts = match state.leg {
    InPort(_) => InPort(departs=state.launch().unwrap().ready_at)
    Underway(crossing=c, ..) =>
      Underway(arrives=c.forecast().map(at => state.at + at - c.t))
  }
  let run = match state.crossing() {
    Some(c) => {
      let r = reckon(c)
      if r.length <= 0.0 {
        0L
      } else {
        (r.run / r.length * 1000.0).round().to_int64()
      }
    }
    None => 0L
  }
  {
    id,
    name: state.profile,
    crossings: state.ship.crossings,
    whereabouts,
    run,
    officers: state.officers.length().to_int64(),
  }
}

///|
/// The ship's own events at `now`, in Unix seconds, applied in order to
/// `state`: the tick, the promotions an arrived crossing has earned (of the
/// hands for which `officer` holds) and then docking with the stores for
/// the next hop, departure once they are loaded, and the ship's turn. Returns the
/// events and the state after them.
///
/// A `minded` ship's mind, a model on the server, makes its turn and
/// chooses promotions instead: the clock leaves the turn out, and docks an
/// arrived ship by script only `MIND_WAIT` after arrival.
pub fn Profile::due(
  self : Profile,
  state : @core.State,
  now : Int64,
  officer~ : (String) -> Bool,
  minded~ : Bool = false,
) -> (Array[@core.Event], @core.State) {
  let events = []
  let mut s = state
  let push = (e : @core.Event) => {
    // Each event is chosen to apply; a refusal here is a bug in this function.
    s = s.apply(e) catch {
      err => abort("ship clock: \{err.to_json().stringify()}")
    }
    events.push(e)
  }
  if now > s.at {
    push(Tick(at=now))
  }
  if arrived_at(s) is Some(at) && (!minded || s.at >= at + MIND_WAIT) {
    for pair in promotions(s.crossing().unwrap(), officer~) {
      push(Promoted(crew=pair.0, rank=pair.1))
    }
    push(Docked(stores=stores(legs=s.ship.crossings + 1L)))
  }
  if s.launch() is Some(l) && l.ready_at <= s.at {
    let legs = s.ship.crossings
    if !minded {
      let cruise = self.temperament.cruise(s.ship, distance_ly=hop(legs))
      if cruise != s.ship.cruise {
        push(Cruising(cruise~))
      }
    }
    push(
      Departed(
        plan=self.next_plan(legs~, coils=s.ship.fit.coils, cruise=s.ship.cruise),
      ),
    )
  }
  let (turn, s) = self.respond(s, minded~)
  (events + turn, s)
}

///|
/// What the ship says and chooses at this instant: see `Temperament::turn`
/// underway, and `Temperament::port_ask` once each port stay. Run after the
/// clock and after every crew intent, since either can open a moment.
/// Nothing for a `minded` ship.
pub fn Profile::respond(
  self : Profile,
  state : @core.State,
  minded~ : Bool = false,
) -> (Array[@core.Event], @core.State) {
  guard !minded else { ([], state) }
  if state.leg is InPort(port~) && !port.spoke {
    let e : @core.Event = Asked(post=self.temperament.port_ask(state))
    let s = state.apply(e) catch {
      err => abort("ship turn: \{err.to_json().stringify()}")
    }
    return ([e], s)
  }
  guard state.leg is Underway(crossing~, spoke~) && crossing.arrived_at is None else {
    ([], state)
  }
  let events : Array[@core.Event] = self.temperament
    .turn(crossing, spoke)
    .map(Act::event)
  let s = events.fold(init=state, (s, e) => {
    s.apply(e) catch {
      err => abort("ship turn: \{err.to_json().stringify()}")
    }
  })
  (events, s)
}

///|
pub fn Act::event(self : Act) -> @core.Event {
  match self {
    Refit(refit) => Refitting(refit~)
    Ask(post) => Asked(post~)
  }
}

///|
/// The next instant, in Unix seconds, at which the ship has something to
/// do: a rate boundary of the crossing, its arrival, or the stores loaded. Never before `state.at`. For a `minded` ship, arrival is followed
/// by `MIND_WAIT`.
pub fn Profile::wake(
  _self : Profile,
  state : @core.State,
  minded~ : Bool = false,
) -> Int64 {
  match state.leg {
    InPort(_) => state.launch().unwrap().ready_at.max(state.at)
    Underway(crossing~, ..) =>
      if arrived_at(state) is Some(at) {
        if minded {
          (at + MIND_WAIT).max(state.at)
        } else {
          state.at
        }
      } else {
        state.at + crossing.next_boundary()
      }
  }
}

///|
/// Longest the ship clock waits between advances of one ship, in seconds,
/// so a changed clock or a missed instant is caught within a minute.
pub const MAX_SLEEP : Int64 = 60L

///|
/// A ship in service: its id in the API and the log, the profile and seed it
/// was commissioned with, and its place in the clock's minute.
pub(all) struct Berth {
  id : String
  profile : Profile
  seed : Int64
  /// Seconds into each minute at which the clock advances this ship, and
  /// how long after each of its instants. Berths have different lags so
  /// ships never take their turns, and later call a model, in the same
  /// second. Only timing: nothing replayed depends on it.
  lag : Int64
} derive(Debug, Eq)

///|
/// The ships the server flies, each with its own lag.
pub fn fleet() -> Array[Berth] {
  let ps = profiles()
  let berths = [("tigress", ps[1]), ("scorpion", ps[2]), ("flea", ps[3])]
  let n = berths.length().to_int64()
  berths.mapi((i, b) => {
    id: b.0,
    profile: b.1,
    seed: 1L,
    lag: i.to_int64() * MAX_SLEEP / n,
  })
}

///|
/// The profile a ship was commissioned under.
pub fn profile_named(name : String) -> Profile? {
  profiles().iter().find_first(p => p.name == name)
}

///|
/// The ship's first event.
pub fn Berth::commission(self : Berth) -> @core.Event {
  Commissioned(
    ship=self.profile.ship(seed=self.seed),
    profile=self.profile.name,
  )
}

///|
/// When, in Unix seconds, the clock should next advance this ship after
/// `now`: `lag` after the ship's next instant, or at its next slot in the
/// minute, whichever is sooner. Always after `now`, and `lag` after it if
/// the ship is overdue.
pub fn Berth::next_advance(
  self : Berth,
  state : @core.State,
  now : Int64,
  minded~ : Bool = false,
) -> Int64 {
  let into = ((self.lag - now) % MAX_SLEEP + MAX_SLEEP) % MAX_SLEEP
  let slot = now + (if into == 0L { MAX_SLEEP } else { into })
  let due = self.profile.wake(state, minded~) + self.lag
  // An overdue ship, as after a restart, keeps its lag from now.
  let due = if due <= now { now + 1L + self.lag } else { due }
  due.min(slot)
}
