///|
/// When the voyage under test leaves port, in Unix seconds.
const DEPART_AT : Int64 = 1_800_000_000L

///|
/// `ship` in port at `DEPART_AT` with its stores loaded.
fn ready(ship : @core.Ship) -> @core.State {
  {
    ..@core.State::initial(ship, profile="test"),
    at: DEPART_AT,
    leg: InPort(port=@core.Port::new(DEPART_AT, 0)),
  }
}

///|
/// `ship` underway on `plan`, ticked to `DEPART_AT`.
fn underway(plan : @core.Plan, ship : @core.Ship) -> @core.State {
  ready(ship).apply(Departed(plan~)) catch {
    _ => panic()
  }
}

///|
/// The crossing event as the log would carry it.
fn as_event(e : @core.CrossingEvent) -> @core.Event {
  match e {
    Elapsed(_) => panic()
    Posted(crew~, post~) => Crew(crew~, intent=Posted(post~))
    Left(crew~) => Crew(crew~, intent=Left)
    Made(crew~) => Crew(crew~, intent=Made)
    Crafted(crew~, craft~) => Crew(crew~, intent=Crafted(craft~))
    Watched(crew~, ticks~) => Crew(crew~, intent=Watched(ticks~))
    Ordered(crew~, order~) => Crew(crew~, intent=Ordered(order~))
    Refitting(refit~) => Refitting(refit~)
    Asked(post~) => Asked(post~)
    Promoted(crew~, rank~) => Promoted(crew~, rank~)
  }
}

///|
/// A voyage driven by an arbitrary schedule, as `drive_schedule` drives a
/// crossing: tick a little later, then apply the event if it applies.
fn state_schedule(
  plan : @core.Plan,
  ship : @core.Ship,
  steps : Array[(Int32, Int32, Int64)],
) -> @core.State {
  let mut s = underway(plan, ship)
  for step in steps {
    let (kind, slot, arg) = step
    s = s.apply(Tick(at=s.at + fold64(arg, 5400L) + 1L)) catch { _ => s }
    s = s.apply(as_event(event_of(kind, slot, arg))) catch { _ => s }
  }
  s
}

///|
fn crossing_of(s : @core.State) -> @core.Crossing {
  s.crossing().unwrap()
}

///|
test "a voyage departs, arrives, docks and departs again" {
  let s = underway(plan20(), ship())
  let s = s.apply(Crew(crew="ann", intent=Posted(post=Drive))) catch {
    _ => panic()
  }
  let c = crossing_of(s)
  let at = c.forecast().unwrap()
  let s = s.apply(Tick(at=s.at + at)) catch { _ => panic() }
  inspect(crossing_of(s).arrived_at == Some(at), content="true")
  let s = s.apply(Docked(stores=0)) catch { _ => panic() }
  debug_inspect(
    s.leg,
    content=(
      #|InPort(port={ since: 1800053855, stores: 0, needed: 0, ask: None, spoke: false })
    ),
  )
  inspect(s.ship.crossings, content="1")
  inspect(s.ship.records.contains("ann"), content="true")
  let s = s.apply(Departed(plan=plan_short())) catch { _ => panic() }
  inspect(crossing_of(s).ship.crossings, content="1")
}

///|
test "a tick that is not later changes nothing" {
  let s = underway(plan20(), ship())
  let s = s.apply(Tick(at=s.at + 60)) catch { _ => panic() }
  assert_eq(s.apply(Tick(at=s.at)), s)
  assert_eq(s.apply(Tick(at=s.at - 3600)), s)
  assert_eq(s.apply(Tick(at=-1)), s)
}

///|
test "rejections" {
  let reject = (state : @core.State, event) => {
    try state.apply(event) catch {
      err => err
    } noraise {
      _ => fail("expected a rejection")
    }
  }
  let port = @core.State::initial(ship(), profile="test")
  debug_inspect(
    reject(port, Crew(crew="ann", intent=Left)),
    content=(
      #|NotSigned(crew="ann")
    ),
  )
  debug_inspect(
    reject(port, Refitting(refit=Some(Plating))),
    content="NotUnderway(event=Refitting(refit=Some(Plating)))",
  )
  debug_inspect(
    reject(port, Docked(stores=0)),
    content=(
      #|NotArrived(event=Docked(stores=0))
    ),
  )
  let sea = underway(plan20(), ship())
  debug_inspect(
    reject(sea, Docked(stores=0)),
    content=(
      #|NotArrived(event=Docked(stores=0))
    ),
  )
  debug_inspect(
    reject(sea, Departed(plan=plan20())),
    content=(
      #|NotInPort(
      #|  event=Departed(
      #|    plan={
      #|      burn: 10779000000,
      #|      coast: 18838000000,
      #|      eta_rate: 1308460,
      #|      coast_rate: 760500,
      #|    },
      #|  ),
      #|)
    ),
  )
  debug_inspect(
    reject(sea, Crew(crew="ann", intent=Left)),
    content=(
      #|NotSigned(crew="ann")
    ),
  )
}

///|
test "the ship's ask records the moment it was made" {
  let s = underway(plan20(), ship())
  let s = s.apply(Asked(post=Some(Drive))) catch { _ => panic() }
  guard s.leg is Underway(crossing~, spoke~) else { panic() }
  assert_eq(spoke, Some(crossing.moment()))
  assert_eq(crossing.ask, Some(Drive))
}

///|
test "law: one long gap of ticks equals two short ones" {
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], (Int32, Int32, Int32), Int64, Int64),
  ) => {
    let (steps, fit, a, b) = input
    let a = fold64(a, 100_000L) + 1L
    let b = fold64(b, 100_000L) + 1L
    let s = state_schedule(plan20(), any_ship(fit, 333_333), steps)
    let whole = s.apply(Tick(at=s.at + a + b)) catch { _ => panic() }
    let split = (s.apply(Tick(at=s.at + a)) catch { _ => panic() }).apply(
      Tick(at=s.at + a + b),
    ) catch {
      _ => panic()
    }
    whole == split
  })
}

///|
test "law: no schedule of intents and ticks leaves the envelope" {
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], Bool, (Int32, Int32, Int32), Int32),
  ) => {
    let (steps, short, fit, hull) = input
    let plan = if short { plan_short() } else { plan20() }
    let c = crossing_of(state_schedule(plan, any_ship(fit, hull), steps))
    let at = c.forecast().unwrap()
    plan.fastest() <= at && at <= plan.slowest()
  })
}

///|
test "law: ticking to the forecast arrives exactly then" {
  let mut checked = 0
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], (Int32, Int32, Int32), Int32),
  ) => {
    let (steps, fit, hull) = input
    let s = state_schedule(plan20(), any_ship(fit, hull), steps)
    let c = crossing_of(s)
    guard c.arrived_at is None else { true }
    let at = c.forecast().unwrap()
    let left = at - c.t
    let early = crossing_of(s.apply(Tick(at=s.at + left - 1L)) catch { _ => s })
    let on_time = crossing_of(
      s.apply(Tick(at=s.at + left)) catch {
        _ => panic()
      },
    )
    checked += 1
    (left == 1L || early.arrived_at is None) && on_time.arrived_at == Some(at)
  })
  assert_true(checked > 0)
}

///|
test "law: a voyage survives a JSON round trip" {
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Int32)) => {
    let (steps, hull) = input
    let s = state_schedule(plan20(), ship(hull=hull_of(hull)), steps)
    let back : @core.State = @json.from_json(s.to_json()) catch { _ => panic() }
    back == s
  })
}

///|
test "wire format" {
  json_inspect(
    @core.Proposal::{ id: 2, crew: "ann", intent: Watched(ticks=3600), },
    content={
      "id": "2",
      "crew": "ann",
      "intent": ["Watched", { "ticks": "3600" }],
    },
  )
}

///|
test "a proposal cannot name a server event" {
  let tick : Json = {
    "id": "1",
    "crew": "ann",
    "intent": ["Tick", { "at": "9" }],
  }
  let decoded : @core.Proposal? = Some(@json.from_json(tick)) catch {
    _ => None
  }
  debug_inspect(decoded, content="None")
}

///|
test "replay begins at the commission, and only there" {
  let s = @core.replay(
    [
      @core.Event::Commissioned(ship=ship(), profile="test"),
      Tick(at=DEPART_AT - 600),
      Tick(at=DEPART_AT),
      Departed(plan=plan20()),
      Crew(crew="ann", intent=Posted(post=Hull)),
      Tick(at=DEPART_AT + 60),
    ].iter(),
  ).unwrap()
  inspect(crossing_of(s).t, content="60")
  inspect(crossing_of(s).count(Hull), content="1")
  debug_inspect(@core.replay([].iter()), content="None")
  let late = try @core.replay([@core.Event::Tick(at=1)].iter()) catch {
    err => Some(err)
  } noraise {
    _ => None
  }
  debug_inspect(
    late,
    content=(
      #|Some(NotFirst(event=Tick(at=1)))
    ),
  )
  let twice = try s.apply(Commissioned(ship=ship(), profile="test")) catch {
    NotFirst(_) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(twice, content="true")
}

///|
test "a ship chooses its cruise in port, and keeps it" {
  let s = ready(ship())
  inspect(s.ship.cruise, content="1000")
  let s = s.apply(Cruising(cruise=750)) catch { _ => panic() }
  inspect(s.ship.cruise, content="750")
  let s = s.apply(Departed(plan=plan20())) catch { _ => panic() }
  inspect(s.ship.cruise, content="750")
  let refused : Result[_, @core.Rejected] = Ok(s.apply(Cruising(cruise=500))) catch {
    e => Err(e)
  }
  inspect(refused is Err(@core.NotInPort(_)), content="true")
  let s = @core.State::initial(ship(), profile="test")
  for cruise in [0L, 1001L] {
    let refused : Result[_, @core.Rejected] = Ok(s.apply(Cruising(cruise~))) catch {
      e => Err(e)
    }
    inspect(refused is Err(@core.NoSuchCruise(_)), content="true")
  }
}

///|
/// A ship in port since `DEPART_AT` with `stores` left to load and `posts`
/// named by its officers, `crew 1` onwards.
fn loading(
  stores : Int64,
  posts : Array[@core.Post],
  hull~ : Int64 = @core.HULL_FULL / 2L,
) -> @core.State {
  let s = @core.State::initial(ship(hull~), profile="test")
  let mut s : @core.State = {
    ..s,
    at: DEPART_AT,
    leg: InPort(port=@core.Port::new(DEPART_AT, stores)),
  }
  for i, post in posts {
    s = s.apply(Crew(crew="crew \{i + 1}", intent=Posted(post~))) catch {
      _ => panic()
    }
  }
  s
}

///|
fn stores_of(s : @core.State) -> Int64 {
  guard s.leg is InPort(port~) else { panic() }
  port.stores
}

///|
fn tick(s : @core.State, ticks : Int64) -> @core.State {
  s.apply(Tick(at=s.at + ticks)) catch {
    _ => panic()
  }
}

///|
test "an empty ship's stores run out at stores / DOCKHANDS ticks" {
  let s = loading(28_800, [])
  let ticks = 28_800L / @core.DOCKHANDS
  inspect(stores_of(tick(s, ticks - 1L)), content="4")
  inspect(stores_of(tick(s, ticks)), content="0")
  debug_inspect(
    s.launch().map(l => l.ready_at - DEPART_AT),
    content="Some(7200)",
  )
}

///|
test "the drive loads stores, the hull mends without moving the departure, craft does neither" {
  let idle = loading(28_800, [])
  let drive = loading(28_800, [Drive])
  let hull = loading(28_800, [Hull])
  let craft = loading(28_800, [Craft])
  let ready = (s : @core.State) => s.launch().unwrap().ready_at - DEPART_AT
  inspect(ready(drive), content="3600")
  inspect(ready(hull), content="7200")
  inspect(ready(craft), content="7200")
  let hull_after = (s : @core.State) => tick(s, 3600).ship.hull
  inspect(hull_after(idle), content="626000000")
  // The ship's fit mends 28,000 a tick for each hand on the hull.
  inspect(hull_after(hull), content="726800000")
  inspect(hull_after(craft), content="626000000")
  inspect(hull_after(drive), content="626000000")
  assert_eq(stores_of(tick(craft, 3600)), stores_of(tick(idle, 3600)))
  assert_eq(stores_of(tick(hull, 3600)), stores_of(tick(idle, 3600)))
}

///|
test "the yard stops at a full hull" {
  let s = tick(
    loading(28_800, [Hull, Hull], hull=@core.HULL_FULL - 1000L),
    7200,
  )
  inspect(s.ship.hull == @core.HULL_FULL, content="true")
}

///|
test "the ship departs only once the stores are loaded" {
  let s = loading(28_800, [Drive])
  let early = try tick(s, 3599).apply(Departed(plan=plan20())) catch {
    err => Some(err)
  } noraise {
    _ => None
  }
  debug_inspect(early, content="Some(NotReady(stores=8))")
  let ready = s.launch().unwrap().ready_at
  let s = s.apply(Tick(at=ready)).apply(Departed(plan=plan20())) catch {
      _ => panic()
    }
  inspect(s.crossing().unwrap().count(Drive), content="1")
}

///|
test "the launch forecasts the hull at departure" {
  let s = loading(28_800, [Drive, Hull])
  let l = s.launch().unwrap()
  debug_inspect(
    l,
    content=(
      #|{ load: 8, mend: 63000, ready_at: 1800003600, hull: 726800000 }
    ),
  )
  assert_eq(tick(s, l.ready_at - s.at).ship.hull, l.hull)
}

///|
test "law: ready_at is the first tick at which the ship may depart" {
  @qc.quick_check_fn((input : (Int64, Array[Int32])) => {
    let (stores, picks) = input
    let stores = fold64(stores, 100_000L)
    let posts : Array[@core.Post] = [Drive, Hull, Craft]
    let posts = picks.map(p => posts[(p % 3).abs()])
    let s = loading(stores, posts)
    let ready = s.launch().unwrap().ready_at
    let departs = (s : @core.State) => {
      try s.apply(Departed(plan=plan20())) catch {
        _ => false
      } noraise {
        _ => true
      }
    }
    let at = (t : Int64) => s.apply(Tick(at=t)) catch { _ => panic() }
    (ready == s.at || !departs(at(ready - 1L))) && departs(at(ready))
  })
}

///|
test "docking loads stores for the next leg and the yard starts from the arrived hull" {
  let s = underway(plan20(), ship(hull=@core.HULL_FULL / 2L))
  let c = crossing_of(s)
  let s = s.apply(Tick(at=s.at + c.forecast().unwrap())) catch { _ => panic() }
  let arrived = crossing_of(s).hull
  let s = s.apply(Docked(stores=28_800)) catch { _ => panic() }
  inspect(s.ship.hull == arrived, content="true")
  guard s.leg is InPort(port~) else { panic() }
  inspect(port.stores, content="28800")
  inspect(port.since == s.at, content="true")
}

///|
test "a ship enters service with ten minutes of stores to load" {
  let s = @core.State::initial(ship(), profile="test").apply(Tick(at=DEPART_AT)) catch {
    _ => panic()
  }
  inspect(stores_of(s), content="2400")
  debug_inspect(
    s.launch().map(l => l.ready_at - DEPART_AT),
    content="Some(600)",
  )
}

///|
test "the ship's ask in port" {
  let s = loading(28_800, [])
  let s = s.apply(Asked(post=Some(Drive))) catch { _ => panic() }
  guard s.leg is InPort(port~) else { panic() }
  debug_inspect(port.ask, content="Some(Drive)")
  inspect(port.spoke, content="true")
}

///|
test "the ship chooses its next world in port, and its stores follow" {
  let s = loading(28_800, [])
  let s = tick(s, 1800)
  inspect(stores_of(s), content="21600")
  // A longer leg: what was loaded counts toward the new stores.
  let s = s.apply(Bound(world="Oaxaca", stores=36_000)) catch { _ => panic() }
  debug_inspect(s.ship.bound, content="Some(\"Oaxaca\")")
  inspect(stores_of(s), content="28800")
  // A shorter one than has been loaded already: nothing left to load.
  let s = s.apply(Bound(world="Occitan", stores=5000)) catch { _ => panic() }
  debug_inspect(s.ship.bound, content="Some(\"Occitan\")")
  inspect(stores_of(s), content="0")
  let s = s.apply(Departed(plan=plan20())) catch { _ => panic() }
  let refused : Result[_, @core.Rejected] = Ok(
    s.apply(Bound(world="Kerala", stores=0)),
  ) catch {
    e => Err(e)
  }
  inspect(refused is Err(@core.NotInPort(_)), content="true")
}

///|
test "docking moves the ship to the world it was bound for" {
  let s = ready(ship())
  let s = s.apply(Bound(world="Oaxaca", stores=0)) catch { _ => panic() }
  let s = s.apply(Departed(plan=plan20())) catch { _ => panic() }
  debug_inspect(crossing_of(s).ship.bound, content="Some(\"Oaxaca\")")
  let c = crossing_of(s)
  let s = s.apply(Tick(at=s.at + c.forecast().unwrap())) catch { _ => panic() }
  let s = s.apply(Docked(stores=0)) catch { _ => panic() }
  debug_inspect(
    (s.ship.came_from, s.ship.from, s.ship.bound),
    content="(None, Some(\"Oaxaca\"), None)",
  )
  let s = s.apply(Bound(world="Tigray", stores=0)) catch { _ => panic() }
  let s = s.apply(Departed(plan=plan20())) catch { _ => panic() }
  let c = crossing_of(s)
  let s = s.apply(Tick(at=s.at + c.forecast().unwrap())) catch { _ => panic() }
  let s = s.apply(Docked(stores=0)) catch { _ => panic() }
  debug_inspect(
    (s.ship.came_from, s.ship.from, s.ship.bound),
    content="(Some(\"Oaxaca\"), Some(\"Tigray\"), None)",
  )
}

///|
test "a ship written before ships chose its course still decodes" {
  let written = ToJson::to_json({
    ..ship(),
    crossings: 3,
    from: Some("Oaxaca"),
  })
  guard written is Object(fields) else { panic() }
  fields.remove("from")
  fields.remove("bound")
  fields.remove("came_from")
  let decoded : @core.Ship = @json.from_json(Json::object(fields)) catch {
    e => fail("\{e}")
  }
  assert_eq(decoded, { ..ship(), crossings: 3, })
}
