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
