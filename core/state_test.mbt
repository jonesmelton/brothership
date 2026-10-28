///|
/// When the voyage under test leaves port, in Unix seconds.
const DEPART_AT : Int64 = 1_800_000_000L

///|
/// `ship` underway on `plan`, ticked to `DEPART_AT`.
fn underway(plan : @core.Plan, ship : @core.Ship) -> @core.State {
  @core.State::initial(ship, profile="test")
  .apply(Tick(at=DEPART_AT))
  .apply(Departed(plan~)) catch {
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
  let s = s.apply(Docked) catch { _ => panic() }
  debug_inspect(
    s.leg,
    content=(
      #|InPort(since=1800050759)
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
      #|NotUnderway(event=Crew(crew="ann", intent=Left))
    ),
  )
  debug_inspect(
    reject(port, Asked(post=Some(Hull))),
    content="NotUnderway(event=Asked(post=Some(Hull)))",
  )
  debug_inspect(reject(port, Docked), content="NotArrived(event=Docked)")
  let sea = underway(plan20(), ship())
  debug_inspect(reject(sea, Docked), content="NotArrived(event=Docked)")
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
      #|Crossing(reason=NotAboard(crew="ann"))
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
