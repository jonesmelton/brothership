///|
/// What a crew member asks to do. Clients send these and nothing else, so a
/// client cannot express a server event such as a tick.
pub(all) enum Intent {
  /// Takes a post, joining the crew if not aboard.
  Posted(post~ : Post)
  Left
  /// Makes the work banked at the craft post, for 100 to 150 percent of it.
  Made
  Crafted(craft~ : Craft)
  /// Stands a watch on the current post for `ticks`.
  Watched(ticks~ : Int64)
  /// Takes a post when a phase begins, or cancels the standing order.
  Ordered(order~ : Order?)
  /// What the engineers build next.
  Refitting(refit~ : Refit?)
} derive(Debug, Eq, ToJson, FromJson)

///|
/// One row of the log: a crew member's intent, or something only the server
/// writes.
pub(all) enum Event {
  /// A ship's first event, and only that: the ship as it enters service, and
  /// the name of the profile the server flies it by (its routes and
  /// temperament). Replay needs nothing outside the log.
  Commissioned(ship~ : Ship, profile~ : String)
  Crew(crew~ : String, intent~ : Intent)
  /// The wall clock reached `at`, in Unix seconds. One tick is one second.
  Tick(at~ : Int64)
  /// The ship leaves port on `plan`, worked out by the server.
  Departed(plan~ : Plan)
  /// The ship docks at the end of an arrived crossing.
  Docked
  /// The ship asks for hands on a post, or stops asking.
  Asked(post~ : Post?)
  /// The ship chooses what its engineers build next.
  Refitting(refit~ : Refit?)
  /// The ship promotes `crew` one rank, at arrival before `Docked`.
  Promoted(crew~ : String, rank~ : Int64)
  /// The ship said `line`, in answer to the happening at log position
  /// `about`. Written by a model and passed by the content gate; changes no
  /// state, so replay never needs the model.
  Spoke(line~ : String, about~ : Int64)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror Rejected {
  /// Crew and ship events need the ship underway.
  NotUnderway(event~ : Event)
  /// The ship departs only from port.
  NotInPort(event~ : Event)
  /// The ship docks only once the crossing has arrived.
  NotArrived(event~ : Event)
  Crossing(reason~ : CrossingRejected)
  /// A ship's log begins with `Commissioned`, and has it nowhere else.
  NotFirst(event~ : Event)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum Leg {
  /// In port since `since`, in Unix seconds.
  InPort(since~ : Int64)
  /// Underway; `spoke` is the moment at which the ship last reconsidered
  /// its ask, if it has this crossing.
  Underway(crossing~ : Crossing, spoke~ : Moment?)
} derive(Debug, Eq, ToJson, FromJson)

///|
/// One ship's voyage. Legs flown so far are `ship.crossings`.
pub(all) struct State {
  /// Unix seconds of the last tick; 0 before the first.
  at : Int64
  /// The profile named when the ship was commissioned.
  profile : String
  /// The ship as it last left port.
  ship : Ship
  leg : Leg
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A voyage that has not begun: `ship` in port, before any tick.
pub fn State::initial(ship : Ship, profile~ : String) -> State {
  { at: 0, profile, ship, leg: InPort(since=0), }
}

///|
/// The state a log begins with, from its first event.
pub fn State::commission(event : Event) -> State raise Rejected {
  guard event is Commissioned(ship~, profile~) else { raise NotFirst(event~) }
  State::initial(ship, profile~)
}

///|
/// The crossing under way, if any.
pub fn State::crossing(self : State) -> Crossing? {
  match self.leg {
    Underway(crossing~, ..) => Some(crossing)
    InPort(_) => None
  }
}

///|
/// The rank `crew` holds: the hand's while aboard, which a promotion at
/// arrival raises before docking, else the ship's record. An ensign's for
/// someone the ship has never carried.
pub fn State::rank(self : State, crew : String) -> Int64 {
  match self.crossing().bind(c => c.hands.get(crew)) {
    Some(h) => h.rank
    None => self.ship.rank(crew)
  }
}

///|
/// Advance `c` by `ticks`, which may exceed what one `Elapsed` takes.
fn elapse(c : Crossing, ticks : Int64) -> Crossing {
  for c = c, left = ticks {
    guard left > 0L else { break c }
    let step = left.min(@math.MAX_TICKS)
    continue c.apply(Elapsed(ticks=step)) catch { _ => panic() }, left - step
  }
}

///|
/// The single transition function. The server calls it to validate and commit;
/// the client calls it to predict. Both must agree, so it stays pure and
/// target-independent.
pub fn State::apply(self : State, event : Event) -> State raise Rejected {
  // Applies `e` to the crossing under way. `speaks` records this instant as
  // the moment the ship last reconsidered.
  let forward = (e : CrossingEvent, speaks : Bool) => {
    guard self.leg is Underway(crossing~, spoke~) else {
      raise NotUnderway(event~)
    }
    let crossing = crossing.apply(e) catch { reason => raise Crossing(reason~) }
    let spoke = if speaks { Some(crossing.moment()) } else { spoke }
    { ..self, leg: Underway(crossing~, spoke~), }
  }
  match event {
    Commissioned(_) => raise NotFirst(event~)
    Tick(at~) if at <= self.at => self
    Tick(at~) =>
      match self.leg {
        // The voyage begins at its first tick.
        InPort(_) if self.at == 0L => { ..self, at, leg: InPort(since=at), }
        InPort(_) => { ..self, at, }
        Underway(crossing~, spoke~) =>
          {
            ..self,
            at,
            leg: Underway(crossing=elapse(crossing, at - self.at), spoke~),
          }
      }
    Departed(plan~) => {
      guard self.leg is InPort(_) else { raise NotInPort(event~) }
      {
        ..self,
        leg: Underway(crossing=Crossing::new(plan, self.ship), spoke=None),
      }
    }
    Docked => {
      guard self.leg is Underway(crossing~, ..) && crossing.dock() is Some(ship) else {
        raise NotArrived(event~)
      }
      { ..self, ship, leg: InPort(since=self.at), }
    }
    Spoke(_) => self
    Promoted(crew~, rank~) => forward(Promoted(crew~, rank~), false)
    Asked(post~) => forward(Asked(post~), true)
    Refitting(refit~) => forward(Refitting(refit~), false)
    Crew(crew~, intent~) =>
      forward(
        match intent {
          Posted(post~) => Posted(crew~, post~)
          Left => Left(crew~)
          Made => Made(crew~)
          Crafted(craft~) => Crafted(crew~, craft~)
          Watched(ticks~) => Watched(crew~, ticks~)
          Ordered(order~) => Ordered(crew~, order~)
          Refitting(refit~) => Refitting(refit~)
        },
        false,
      )
  }
}

///|
/// One ship's log, from its `Commissioned`, replayed. `None` for an empty log.
pub fn replay(events : Iter[Event]) -> State? raise Rejected {
  let mut state = None
  for event in events {
    state = Some(
      match state {
        None => State::commission(event)
        Some(s) => s.apply(event)
      },
    )
  }
  state
}
