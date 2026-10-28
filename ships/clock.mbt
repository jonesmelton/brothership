///|
/// The ship's own events at `now`, in Unix seconds, applied in order to
/// `state`: the tick, docking once the crossing has arrived, departure for
/// the next hop once the port stay is over, and the ship's turn. Returns the
/// events and the state after them.
pub fn Profile::due(
  self : Profile,
  state : @core.State,
  now : Int64,
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
  if s.crossing() is Some(c) && c.arrived_at is Some(_) {
    push(Docked)
  }
  if s.leg is InPort(since~) && s.at >= since + PORT_STAY {
    push(
      Departed(
        plan=self.next_plan(legs=s.ship.crossings, coils=s.ship.fit.coils),
      ),
    )
  }
  let (turn, s) = self.respond(s)
  (events + turn, s)
}

///|
/// What the ship says and chooses at this instant, if underway: see
/// `Temperament::turn`. Run after the clock and after every crew intent,
/// since either can open a moment.
pub fn Profile::respond(
  self : Profile,
  state : @core.State,
) -> (Array[@core.Event], @core.State) {
  guard state.leg is Underway(crossing~, spoke~) && crossing.arrived_at is None else {
    ([], state)
  }
  let events : Array[@core.Event] = self.temperament
    .turn(crossing, spoke)
    .map(act => {
      match act {
        Refit(refit) => Refitting(refit~)
        Ask(post) => Asked(post~)
      }
    })
  let s = events.fold(init=state, (s, e) => {
    s.apply(e) catch {
      err => abort("ship turn: \{err.to_json().stringify()}")
    }
  })
  (events, s)
}

///|
/// The next instant, in Unix seconds, at which the ship has something to
/// do: a rate boundary of the crossing, its arrival, or the end of the port
/// stay. Never before `state.at`.
pub fn Profile::wake(_self : Profile, state : @core.State) -> Int64 {
  match state.leg {
    InPort(since~) => (since + PORT_STAY).max(state.at)
    Underway(crossing~, ..) =>
      if crossing.arrived_at is Some(_) {
        state.at
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
) -> Int64 {
  let into = ((self.lag - now) % MAX_SLEEP + MAX_SLEEP) % MAX_SLEEP
  let slot = now + (if into == 0L { MAX_SLEEP } else { into })
  let due = self.profile.wake(state) + self.lag
  // An overdue ship, as after a restart, keeps its lag from now.
  let due = if due <= now { now + 1L + self.lag } else { due }
  due.min(slot)
}
