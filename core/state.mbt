///|
/// What a crew member asks to do. Clients send these and nothing else, so a
/// client cannot express a server event such as a tick.
pub(all) enum Intent {
  /// Signs on to the ship, without a post.
  Signed
  /// Takes a post, signing on if not aboard. In port, names the post to
  /// take at departure.
  Posted(post~ : Post)
  /// Stands down from the post, staying aboard.
  Left
  /// Leaves the ship when it next docks, or at once in port; `false`
  /// stays after all.
  Leaving(leaving~ : Bool)
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
  /// The ship docks at the end of an arrived crossing, with `stores` to load
  /// for the next leg, sized by the server.
  Docked(stores~ : Int64)
  /// The ship asks for hands on a post, or stops asking.
  Asked(post~ : Post?)
  /// The ship chooses what its engineers build next.
  Refitting(refit~ : Refit?)
  /// The ship promotes `crew` one rank, at arrival before `Docked`.
  Promoted(crew~ : String, rank~ : Int64)
  /// The ship chooses, in port, the γ it coasts at from its next departure,
  /// in thousandths of its cap.
  Cruising(cruise~ : Int64)
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
  /// The ship departs only once its stores are loaded; `stores` are left.
  NotReady(stores~ : Int64)
  /// The ship docks only once the crossing has arrived.
  NotArrived(event~ : Event)
  Crossing(reason~ : CrossingRejected)
  /// A ship's log begins with `Commissioned`, and has it nowhere else.
  NotFirst(event~ : Event)
  /// A cruise is above zero and at most `CRUISE_FULL`.
  NoSuchCruise(cruise~ : Int64)
  /// Only an officer aboard can do this.
  NotSigned(crew~ : String)
  /// The officer is aboard `ship`, and an officer serves on one ship at a
  /// time. Refused by the store, which sees every ship, never by
  /// `State::apply`.
  AboardAnother(ship~ : String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum Leg {
  InPort(port~ : Port)
  /// Underway; `spoke` is the moment at which the ship last reconsidered
  /// its ask, if it has this crossing.
  Underway(crossing~ : Crossing, spoke~ : Moment?)
} derive(Debug, Eq, ToJson, FromJson)

///|
/// An officer aboard, from signing on until discharged at a dock. Kept
/// across port stays, unlike a `Hand`.
pub(all) struct Officer {
  /// The post to take at the next departure, if any. Set at docking from
  /// the post held at arrival, and by `Posted` and `Left` in port.
  post : Post?
  /// Leaves at the next dock.
  leaving : Bool
  /// Has acted since the ship last docked or since signing on. Docking
  /// discharges an officer who has not.
  active : Bool
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
  /// The officers aboard, by crew id, in order of signing on.
  officers : Map[String, Officer]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A voyage that has not begun: `ship` in port, before any tick.
pub fn State::initial(ship : Ship, profile~ : String) -> State {
  { at: 0, profile, ship, leg: InPort(port=Port::new(0, 0)), officers: {}, }
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
        InPort(port~) if self.at == 0L =>
          { ..self, at, leg: InPort(port={ ..port, since: at, }), }
        InPort(port~) => self.load(port, at)
        Underway(crossing~, spoke~) =>
          {
            ..self,
            at,
            leg: Underway(crossing=elapse(crossing, at - self.at), spoke~),
          }
      }
    Departed(plan~) => {
      guard self.leg is InPort(port~) else { raise NotInPort(event~) }
      guard port.stores == 0L else { raise NotReady(stores=port.stores) }
      // Officers take the posts they named in port.
      let mut c = Crossing::new(plan, self.ship)
      for crew, o in self.officers {
        if o.post is Some(post) {
          c = c.apply(Posted(crew~, post~)) catch { _ => panic() }
        }
      }
      { ..self, leg: Underway(crossing=c, spoke=None), }
    }
    Docked(stores~) => {
      guard self.leg is Underway(crossing~, ..) && crossing.dock() is Some(ship) else {
        raise NotArrived(event~)
      }
      let officers : Map[String, Officer] = Map([])
      for crew, o in self.officers {
        if o.active && !o.leaving {
          let post = crossing.hands.get(crew).map(h => h.post)
          officers[crew] = { post, leaving: false, active: false, }
        }
      }
      let port = Port::new(self.at, stores.max(0L))
      { ..self, ship, leg: InPort(port~), officers, }
    }
    Spoke(_) => self
    Cruising(cruise~) => {
      guard cruise > 0L && cruise <= CRUISE_FULL else {
        raise NoSuchCruise(cruise~)
      }
      guard self.leg is InPort(_) else { raise NotInPort(event~) }
      { ..self, ship: { ..self.ship, cruise, }, }
    }
    Promoted(crew~, rank~) => forward(Promoted(crew~, rank~), false)
    Asked(post~) =>
      match self.leg {
        InPort(port~) =>
          { ..self, leg: InPort(port={ ..port, ask: post, spoke: true, }), }
        Underway(_) => forward(Asked(post~), true)
      }
    Refitting(refit~) => forward(Refitting(refit~), false)
    Crew(crew~, intent~) => {
      let officer = self.officers.get(crew)
      // The officers with `crew` as one who has just acted, signed on if
      // new, and naming `post` for departure if given.
      let acted = (post : Post?) => {
        let officers = self.officers.copy()
        officers[crew] = match (officer, post) {
          (Some(o), None) => { ..o, active: true, }
          (Some(o), Some(_)) => { ..o, post, active: true, }
          (None, _) => { post, leaving: false, active: true, }
        }
        officers
      }
      let signs = intent is (Signed | Posted(_))
      let port_only = self.leg is InPort(_) &&
        !(intent is (Signed | Posted(_) | Left | Leaving(_)))
      guard signs || port_only || officer is Some(_) else {
        raise NotSigned(crew~)
      }
      match (self.leg, intent) {
        (_, Signed) => { ..self, officers: acted(None), }
        (InPort(_), Posted(post~)) => { ..self, officers: acted(Some(post)), }
        (InPort(_), Left) => {
          let officers = acted(None)
          officers[crew] = { ..officers[crew], post: None, }
          { ..self, officers, }
        }
        (InPort(_), Leaving(leaving=true)) => {
          let officers = self.officers.copy()
          officers.remove(crew)
          { ..self, officers, }
        }
        (_, Leaving(leaving~)) => {
          let officers = acted(None)
          officers[crew] = { ..officers[crew], leaving, }
          { ..self, officers, }
        }
        (InPort(_), _) => raise NotUnderway(event~)
        (Underway(_), _) => {
          let s = forward(
            match intent {
              Posted(post~) => Posted(crew~, post~)
              Left => Left(crew~)
              Made => Made(crew~)
              Crafted(craft~) => Crafted(crew~, craft~)
              Watched(ticks~) => Watched(crew~, ticks~)
              Ordered(order~) => Ordered(crew~, order~)
              Refitting(refit~) => Refitting(refit~)
              Signed | Leaving(_) => panic()
            },
            false,
          )
          { ..s, officers: acted(None), }
        }
      }
    }
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
