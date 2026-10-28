///|
test "every hop of the itinerary is 8 to 30 ly" {
  for d in @ships.itinerary {
    assert_true(d >= 8.0 && d <= 30.0)
  }
}

///|
test "every ship in the fleet has a title that agrees with its name" {
  for berth in @ships.fleet() {
    let p = berth.profile
    guard p.title is Some(t) else { fail("\{p.name} has no title") }
    assert_eq("\{t.pennant} \{t.epithet}", p.name)
    assert_true(t.conventional_name.length() > 0, msg=p.name)
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
  let commission = @core.Event::Commissioned(ship~, profile=p.name)
  let mut s = @core.State::commission(commission)
  let log = [commission]
  let mut now = 1_800_000_000L
  let mut docked = 0
  let mut departed = 0
  for _ in 0..<10_000 {
    let (events, next) = p.due(s, now, officer=_ => true)
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
      #|<ArrayView:
      #|  [
      #|    Commissioned(
      #|      ship={
      #|        values: { drive: 1, hull: 3, craft: 2 },
      #|        fit: {
      #|          needed: 5,
      #|          wear: 24000,
      #|          repair: 32000,
      #|          baffles: 0,
      #|          plating: 0,
      #|          injectors: 0,
      #|          coils: 0,
      #|          refit: None,
      #|          progress: 0,
      #|        },
      #|        hull: 1000000000,
      #|        records: {},
      #|        recruits: 0,
      #|        toward_recruit: 0,
      #|        crossings: 0,
      #|        seed: 1,
      #|      },
      #|      profile="EF-147 The Tigress",
      #|    ),
      #|    Tick(at=1800000000),
      #|  ]>
    ),
  )
  guard log[3] is Departed(_) else { fail("expected the departure third") }
  assert_eq(@core.replay(log.iter()), Some(s))
}

///|
test "the ship clock does nothing before the next instant" {
  let p = @ships.profiles()[1]
  let s = @core.State::initial(p.ship(seed=1), profile=p.name)
  let (_, s) = p.due(s, 1_800_000_000L, officer=_ => true)
  inspect(p.wake(s), content="1800000600")
  let (events, _) = p.due(s, 1_800_000_000L, officer=_ => true)
  inspect(events.length(), content="0")
  let (events, _) = p.due(s, 1_800_000_599L, officer=_ => true)
  debug_inspect(events, content="[Tick(at=1800000599)]")
}

///|
test "each berth advances on its own second of the minute" {
  let fleet = @ships.fleet()
  debug_inspect(
    fleet.map(b => (b.id, b.lag)),
    content=(
      #|[("tigress", 0), ("scorpion", 20), ("flea", 40)]
    ),
  )
  let now = 1_800_000_000L
  let slots = fleet.map(b => {
    let s = @core.State::commission(b.commission())
    let (_, s) = b.profile.due(s, now, officer=_ => true)
    b.next_advance(s, now) % @ships.MAX_SLEEP
  })
  debug_inspect(
    slots,
    content=(
      #|[0, 20, 40]
    ),
  )
}

///|
test "a berth acts its lag after the ship's instant" {
  let b = @ships.fleet()[2]
  let s = @core.State::commission(b.commission())
  let (_, s) = b.profile.due(s, 1_800_000_000L, officer=_ => true)
  // The stay ends at +600; the slot in the minute comes first until then.
  let at = b.next_advance(s, 1_800_000_570L)
  inspect(
    at - 1_800_000_000L,
    content=(
      #|580
    ),
  )
  let at = b.next_advance(s, 1_800_000_599L)
  inspect(
    at - 1_800_000_000L,
    content=(
      #|640
    ),
  )
}

///|
test "overdue ships, as after a restart, still advance on different seconds" {
  let now = 1_800_000_007L
  let at = @ships.fleet().map(b => {
    b.next_advance(@core.State::commission(b.commission()), now) - now
  })
  debug_inspect(at, content="[1, 13, 33]")
}
