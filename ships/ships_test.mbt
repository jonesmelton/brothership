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
        Docked(_) => docked += 1
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
  // The first session is in port, loading the first stores.
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
      #|        cruise: 1000,
      #|      },
      #|      profile="EF-147 The Tigress",
      #|    ),
      #|    Tick(at=1800000000),
      #|  ]>
    ),
  )
  debug_inspect(
    log[2:4],
    content=(
      #|<ArrayView: [Asked(post=Some(Hull)), Tick(at=1800000600)]>
    ),
  )
  assert_eq(@core.replay(log.iter()), Some(s))
}

///|
test "the ship clock does nothing before the next instant" {
  let p = @ships.profiles()[1]
  let s = first_port(p)
  let ready = s.launch().unwrap().ready_at
  assert_eq(p.wake(s), ready)
  let (events, _) = p.due(s, s.at, officer=_ => true)
  inspect(events.length(), content="0")
  let (events, _) = p.due(s, ready - 1L, officer=_ => true)
  assert_eq(events, [Tick(at=ready - 1L)])
  let (events, _) = p.due(s, ready, officer=_ => true)
  assert_true(events.iter().any(e => e is Departed(_)))
}

///|
/// `p`'s ship left alone from commissioning to its first dock.
fn first_port(p : @ships.Profile) -> @core.State {
  let mut s = @core.State::commission(
    @core.Event::Commissioned(ship=p.ship(seed=1), profile=p.name),
  ) catch {
    _ => panic()
  }
  let mut now = 1_800_000_000L
  for _ in 0..<10_000 {
    s = p.due(s, now, officer=_ => true).1
    if s.leg is InPort(_) && s.ship.crossings == 1L {
      return s
    }
    now = p.wake(s).max(now + 1L)
  }
  abort("never docked")
}

///|
test "a docked ship loads stores for its next leg, and asks in its temperament" {
  let docked = @ships.profiles()[1:]
    .iter()
    .map(p => {
      let s = first_port(p)
      guard s.leg is InPort(port~) else { panic() }
      (p.temperament.name(), port.stores, port.ask)
    })
  debug_inspect(
    docked.collect(),
    content=(
      #|[
      #|  ("social", 19832, Some(Hull)),
      #|  ("bold", 19832, Some(Drive)),
      #|  ("sly", 19832, Some(Drive)),
      #|]
    ),
  )
  debug_inspect(
    [0L, 1L, 2L, 3L].map(legs => @ships.stores(legs~)),
    content=(
      #|[22612, 19832, 34801, 28753]
    ),
  )
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
  // In port, with the stores far from loaded, only the slot is due.
  let slots = fleet.map(b => {
    let s = first_port(b.profile)
    b.next_advance(s, s.at) % @ships.MAX_SLEEP
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
  let s = first_port(b.profile)
  let ready = s.launch().unwrap().ready_at
  // The slot in the minute comes first until the stores are loaded.
  let early = b.next_advance(s, ready - 30L)
  assert_true(early < ready + b.lag, msg="\{early - ready}")
  inspect(b.next_advance(s, ready - 1L) - ready, content="40")
}

///|
test "overdue ships, as after a restart, still advance on different seconds" {
  let now = 1_800_000_007L
  let at = @ships.fleet().map(b => {
    b.next_advance(@core.State::commission(b.commission()), now) - now
  })
  debug_inspect(at, content="[1, 13, 33]")
}

///|
test "a listing says where the ship is and who is aboard" {
  let p = @ships.profiles()[1]
  let s = first_port(p)
  let s = s.apply(Crew(crew="ann", intent=Signed)) catch { _ => panic() }
  let ready = s.launch().unwrap().ready_at
  let l = @ships.listing("tigress", s)
  assert_eq(l.whereabouts, InPort(departs=ready))
  inspect(l.officers, content="1")
  // Posting to the drive brings the departure forward at once.
  let s = s.apply(Crew(crew="ann", intent=Posted(post=Drive))) catch {
    _ => panic()
  }
  let sooner = s.launch().unwrap().ready_at
  assert_true(sooner < ready)
  assert_eq(@ships.listing("tigress", s).whereabouts, InPort(departs=sooner))
  let (events, s) = p.due(s, sooner, officer=_ => true)
  assert_true(events.iter().any(e => e is Departed(_)))
  let c = s.crossing().unwrap()
  assert_eq(
    @ships.listing("tigress", s).whereabouts,
    Underway(arrives=Some(s.at + c.forecast().unwrap() - c.t)),
  )
}

///|
test "a cruise below the cap coasts slower and erodes the hull less" {
  let route = @ships.Route::default()
  let full = route.plan_with(coils=0)
  let half = route.plan_with(coils=0, cruise=500)
  assert_true(
    half.coast_rate * 2L <= full.coast_rate + 2000L,
    msg="\{half.coast_rate}",
  )
  assert_true(half.fastest() > full.fastest())
  // Erosion per tick goes as the pace squared, so over a coast as the pace.
  let worn = (p : @core.Plan) => {
    p.coast / p.coast_rate * p.coast_rate / 1000L * p.coast_rate
  }
  assert_true(worn(half) < worn(full))
}

///|
test "left alone, a ship sets its temperament's cruise before it departs" {
  let p = @ships.profiles()[3]
  let s = @core.State::commission(
    @core.Event::Commissioned(ship=p.ship(seed=1), profile=p.name),
  )
  let s = p.due(s, 1_800_000_000L, officer=_ => true).1
  let (events, s) = p.due(s, s.launch().unwrap().ready_at, officer=_ => true)
  let cruise = p.temperament.cruise(s.ship, distance_ly=@ships.hop(0))
  assert_true(cruise < @core.CRUISE_FULL)
  assert_true(events.contains(Cruising(cruise~)))
  guard s.crossing() is Some(c) else { fail("not underway") }
  assert_eq(c.plan, p.next_plan(legs=0, coils=0, cruise~))
}
