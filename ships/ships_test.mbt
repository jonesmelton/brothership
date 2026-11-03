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
  let c = @core.Crossing::new(
    p.next_plan(distance_ly=@ships.hop(0), coils=0),
    p.ship(seed=1),
  )
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
test "left alone, the ship clock chooses its course and its log replays" {
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
  // The Tigress is social: its seed picks among the worlds it may reach.
  debug_inspect(
    log.filter_map(e => if e is Bound(world~, ..) { Some(world) } else { None }),
    content=(
      #|["Occitan", "Oaxaca", "Tigray"]
    ),
  )
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
      #|        from: None,
      #|        bound: None,
      #|        came_from: None,
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
      #|  ("social", 36631, Some(Hull)),
      #|  ("bold", 37933, Some(Drive)),
      #|  ("sly", 21555, Some(Drive)),
      #|]
    ),
  )
}

///|
test "stores are sized by the hop to the world chosen, but the first are fixed" {
  let ship = @ships.profiles()[1].ship(seed=1)
  let oaxaca = @ships.world_named("Oaxaca").unwrap()
  inspect(@ships.stores_for(ship, oaxaca), content="2400")
  let ship = { ..ship, crossings: 1, from: Some("Kerala"), }
  inspect(@ships.stores_for(ship, oaxaca), content="28753")
  let ship = { ..ship, from: Some("Tigray"), }
  inspect(
    @ships.stores_for(ship, oaxaca),
    content=(
      #|31226
    ),
  )
}

///|
test "the worlds a ship may leave for: not back, and not two short crossings running" {
  let names = (ws : Array[@ships.World]) => ws.map(w => w.name)
  let ship = @ships.profiles()[1].ship(seed=1)
  // A ship entering service is at the itinerary's first world.
  debug_inspect(
    names(@ships.choices(ship)),
    content=(
      #|["Tigray", "Oaxaca", "Occitan", "The Three Tyrants"]
    ),
  )
  // A ship from before ships chose: its worlds are the itinerary's. It came
  // from Occitan, 13.8 ly off, so the near world is closed this time.
  let legacy = { ..ship, crossings: 2, }
  debug_inspect(
    (
      @ships.origin(legacy).name,
      @ships.came_from(legacy).map(w => w.name),
      names(@ships.choices(legacy)),
    ),
    content=(
      #|("Tigray", Some("Occitan"), ["Kerala", "Oaxaca"])
    ),
  )
  let chosen = {
    ..ship,
    crossings: 5,
    from: Some("Oaxaca"),
    came_from: Some("The Three Tyrants"),
  }
  debug_inspect(
    names(@ships.choices(chosen)),
    content=(
      #|["Kerala", "Tigray", "Occitan"]
    ),
  )
}

///|
test "a short crossing closes the near worlds until the ship has ranged" {
  let names = (ws : Array[@ships.World]) => ws.map(w => w.name)
  // Kerala to Occitan is 15.7 ly: the near worlds are closed at Occitan.
  let short = {
    ..@ships.profiles()[1].ship(seed=1),
    crossings: 1,
    from: Some("Occitan"),
    came_from: Some("Kerala"),
  }
  inspect(@ships.flew_short(short), content="true")
  debug_inspect(
    names(@ships.choices(short)),
    content=(
      #|["Oaxaca", "The Three Tyrants"]
    ),
  )
  // The Three Tyrants to Occitan is 26.3 ly, so the near worlds are open.
  let long = { ..short, came_from: Some("The Three Tyrants"), }
  inspect(@ships.flew_short(long), content="false")
  debug_inspect(
    names(@ships.choices(long)),
    content=(
      #|["Kerala", "Tigray", "Oaxaca"]
    ),
  )
}

///|
test "each temperament's course over many legs, never straight back, never a short one after a short one" {
  let courses = @ships.profiles().map(p => {
    let mut ship = p.ship(seed=1)
    let flown = [@ships.origin(ship).name]
    let mut last = -1.0
    for _ in 0..<8 {
      let to = p.temperament.course(ship)
      assert_true(@ships.choices(ship).contains(to))
      let distance_ly = @ships.origin(ship).distance_to(to)
      if last >= 0.0 && last < @ships.SHORT_CROSSING {
        assert_true(
          distance_ly >= @ships.SHORT_CROSSING,
          msg="\{p.temperament.name()} flew \{distance_ly} after \{last}",
        )
      }
      last = distance_ly
      flown.push(to.name)
      ship = {
        ..ship,
        crossings: ship.crossings + 1L,
        came_from: Some(@ships.origin(ship).name),
        from: Some(to.name),
      }
    }
    "\{p.temperament.name()}: \{flown.join(", ")}"
  })
  debug_inspect(
    courses,
    content=(
      #|[
      #|  "careful: Kerala, Occitan, Oaxaca, The Three Tyrants, Occitan, Tigray, Oaxaca, The Three Tyrants, Occitan",
      #|  "social: Kerala, Occitan, Oaxaca, Tigray, Occitan, Oaxaca, Kerala, The Three Tyrants, Occitan",
      #|  "bold: Kerala, The Three Tyrants, Occitan, Oaxaca, Tigray, Kerala, The Three Tyrants, Occitan, Oaxaca",
      #|  "sly: Kerala, Tigray, The Three Tyrants, Occitan, Kerala, Tigray, The Three Tyrants, Occitan, Kerala",
      #|]
    ),
  )
}

///|
test "a minded ship's clock chooses its next world only once the stores are loaded" {
  let p = @ships.profiles()[1]
  let s = first_port(p)
  let s = {
    ..s,
    ship: { ..s.ship, bound: None, },
    leg: InPort(port=@core.Port::new(s.at, 100)),
  }
  let (events, _) = p.due(s, s.at + 1L, officer=_ => true, minded=true)
  inspect(events.iter().any(e => e is Bound(..)), content="false")
  let (events, after) = p.due(s, s.at + 1000L, officer=_ => true, minded=true)
  let world = p.temperament.course(s.ship).name
  inspect(
    events.iter().any(e => e is Bound(world=w, ..) && w == world),
    content="true",
  )
  // The world is farther than the stores loaded, so the ship waits for more.
  inspect(after.leg is InPort(_), content="true")
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
  // Shifted in time so the stores are loaded at second 50 of a minute,
  // when the berth's next slot is later than its lag after them.
  let r = s.launch().unwrap().ready_at
  let d = (50L - r % 60L + 60L) % 60L
  guard s.leg is InPort(port~) else { panic() }
  let s = {
    ..s,
    at: s.at + d,
    leg: InPort(port={ ..port, since: port.since + d, }),
  }
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
  assert_eq(l.run, 0L)
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
  assert_eq(@ships.listing("tigress", s).run, 0L)
  let later = p.due(s, s.at + 14_400L, officer=_ => true).1
  let run = @ships.listing("tigress", later).run
  assert_true(run > 0L && run < 1000L)
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
  let distance_ly = @ships.origin(s.ship).distance_to(
    @ships.bound_for(s).unwrap(),
  )
  let cruise = p.temperament.cruise(s.ship, distance_ly~)
  assert_true(cruise < @core.CRUISE_FULL)
  assert_true(events.contains(Cruising(cruise~)))
  guard s.crossing() is Some(c) else { fail("not underway") }
  assert_eq(c.plan, p.next_plan(distance_ly~, coils=0, cruise~))
}

///|
/// The worlds a ship visits if its model always asks for the nearest world
/// open to it, as `Temperament::ranging` lets that stand.
fn nearest_every_time(p : @ships.Profile) -> Array[String] {
  let mut ship = p.ship(seed=1)
  let mut before : @ships.World? = None
  let route = [@ships.origin(ship).name]
  for _ in 0..<10 {
    let here = @ships.origin(ship)
    let nearest = @ships.Temperament::Careful.course(ship)
    let to = p.temperament.ranging(ship, nearest, before~)
    route.push(to.name)
    before = @ships.came_from(ship)
    ship = {
      ..ship,
      crossings: ship.crossings + 1,
      from: Some(to.name),
      came_from: Some(here.name),
    }
  }
  route
}

///|
test "the nearest world twice running gives way to the ship's temperament" {
  let ps = @ships.profiles()
  let routes = [ps[1], ps[2], ps[3]].map(nearest_every_time)
  assert_true(routes[0] != routes[1])
  assert_true(routes[1] != routes[2])
  assert_true(routes[0] != routes[2])
}

///|
test "a first choice of the nearest world stands" {
  let p = @ships.profiles()[2]
  let ship = p.ship(seed=1)
  let nearest = @ships.Temperament::Careful.course(ship)
  assert_eq(p.temperament.ranging(ship, nearest, before=None), nearest)
}

///|
test "the nearest world stands after a crossing to a farther one" {
  let p = @ships.profiles()[2]
  let ship = {
    ..p.ship(seed=1),
    crossings: 2,
    from: Some("Tigray"),
    came_from: Some("Kerala"),
  }
  let nearest = @ships.Temperament::Careful.course(ship)
  let before = @ships.world_named("Occitan")
  // From Kerala, having come from Occitan, Oaxaca was nearer than Tigray.
  assert_eq(p.temperament.ranging(ship, nearest, before~), nearest)
}

///|
test "a world other than the nearest always stands" {
  let p = @ships.profiles()[2]
  let ship = {
    ..p.ship(seed=1),
    crossings: 2,
    from: Some("Occitan"),
    came_from: Some("Kerala"),
  }
  let far = @ships.world_named("The Three Tyrants").unwrap()
  assert_eq(p.temperament.ranging(ship, far, before=None), far)
}
