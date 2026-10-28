///|
test "every hop of the itinerary is 8 to 30 ly" {
  for d in @ships.itinerary {
    assert_true(d >= 8.0 && d <= 30.0)
  }
}

///|
test "the ship asks once per moment and refits only on change" {
  let p = @ships.profiles()[1]
  let c = @core.Crossing::new(p.next_plan(legs=0, coils=0), p.ship(seed=1))
  let first = p.temperament.turn(c, None)
  debug_inspect(
    first,
    content=(
      #|[Refit(Some(Plating)), Ask(Some(Drive))]
    ),
  )
  inspect(p.temperament.turn(c, Some(c.moment())).length(), content="1")
}

///|
test "left alone, the ship clock flies the itinerary and its log replays" {
  let p = @ships.profiles()[1]
  let ship = p.ship(seed=1)
  let mut s = @core.State::initial(ship)
  let log = []
  let mut now = 1_800_000_000L
  let mut docked = 0
  let mut departed = 0
  for _ in 0..<10_000 {
    let (events, next) = p.due(s, now)
    for e in events {
      match e {
        Docked => docked += 1
        Departed(_) => departed += 1
        _ => ()
      }
    }
    log.append(events)
    s = next
    guard docked < 2 else { break }
    now = p.wake(s).max(now + 1L)
  }
  debug_inspect((departed, docked, s.ship.crossings), content="(2, 2, 2)")
  // The first session is in port, for the whole stay.
  debug_inspect(
    log[:2],
    content=(
      #|<ArrayView: [Tick(at=1800000000), Tick(at=1800000600)]>
    ),
  )
  guard log[2] is Departed(_) else { fail("expected the departure third") }
  assert_eq(@core.replay(ship, log.iter()), s)
}

///|
test "the ship clock does nothing before the next instant" {
  let p = @ships.profiles()[1]
  let s = @core.State::initial(p.ship(seed=1))
  let (_, s) = p.due(s, 1_800_000_000L)
  inspect(p.wake(s), content="1800000600")
  let (events, _) = p.due(s, 1_800_000_000L)
  inspect(events.length(), content="0")
  let (events, _) = p.due(s, 1_800_000_599L)
  debug_inspect(events, content="[Tick(at=1800000599)]")
}
