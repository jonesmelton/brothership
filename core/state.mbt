///|
pub(all) enum Event {
  Elapsed(ticks~ : Int64)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror Rejected {
  NonPositiveTicks(ticks~ : Int64)
  ClockOverflow(clock~ : Int64, ticks~ : Int64)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct State {
  clock : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn State::initial() -> State {
  { clock: 0, }
}

///|
/// The single transition function. The server calls it to validate and commit;
/// the client calls it to predict. Both must agree, so it stays pure and
/// target-independent.
pub fn State::apply(self : State, event : Event) -> State raise Rejected {
  match event {
    Elapsed(ticks~) => {
      guard ticks > 0 else { raise NonPositiveTicks(ticks~) }
      guard @math.try_advance(self.clock, ticks) is Some(clock) else {
        raise ClockOverflow(clock=self.clock, ticks~)
      }
      { clock, }
    }
  }
}

///|
pub fn replay(events : Iter[Event]) -> State raise Rejected {
  let mut state = State::initial()
  for event in events {
    state = state.apply(event)
  }
  state
}
