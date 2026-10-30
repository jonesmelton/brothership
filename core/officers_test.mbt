///|
/// `s` ticked to its arrival and docked.
fn dock(s : @core.State) -> @core.State {
  let c = crossing_of(s)
  let at = c.forecast().unwrap()
  s.apply(Tick(at=s.at + at - c.t)).apply(Docked(stores=0)) catch {
    _ => panic()
  }
}

///|
fn act(s : @core.State, crew : String, intent : @core.Intent) -> @core.State {
  s.apply(Crew(crew~, intent~)) catch {
    _ => panic()
  }
}

///|
fn in_port() -> @core.State {
  @core.State::initial(ship(), profile="test").apply(Tick(at=DEPART_AT)) catch {
    _ => panic()
  }
}

///|
fn depart(s : @core.State) -> @core.State {
  s.apply(Departed(plan=plan20())) catch {
    _ => panic()
  }
}

///|
test "signing on in port puts an officer aboard, to take their post at departure" {
  let s = act(in_port(), "ann", Signed)
  debug_inspect(
    s.officers.get("ann"),
    content="Some({ post: None, leaving: false, active: true })",
  )
  let s = act(s, "bo", Posted(post=Hull))
  debug_inspect(
    s.officers.get("bo"),
    content="Some({ post: Some(Hull), leaving: false, active: true })",
  )
  let c = crossing_of(depart(s))
  inspect(c.hands.contains("ann"), content="false")
  debug_inspect(c.hands.get("bo").map(h => h.post), content="Some(Hull)")
}

///|
test "taking a post underway signs on" {
  let s = act(depart(in_port()), "ann", Posted(post=Drive))
  inspect(s.officers.contains("ann"), content="true")
}

///|
test "standing down leaves an officer aboard without a post" {
  let s = act(depart(in_port()), "ann", Posted(post=Drive))
  let s = act(s, "ann", Left)
  inspect(crossing_of(s).hands.contains("ann"), content="false")
  inspect(s.officers.contains("ann"), content="true")
  let s = act(dock(s), "ann", Posted(post=Craft))
  let s = act(s, "ann", Left)
  debug_inspect(s.officers.get("ann").map(o => o.post), content="Some(None)")
}

///|
test "docking discharges whoever did nothing since the last dock, and keeps the rest at their posts" {
  let s = act(in_port(), "idle", Signed)
  let s = depart(s)
  let s = act(s, "ann", Posted(post=Drive))
  let s = act(s, "bo", Posted(post=Hull))
  let s = dock(s)
  // Signing on is acting.
  assert_eq(s.officers.keys().collect(), ["idle", "ann", "bo"])
  debug_inspect(
    s.officers.get("ann"),
    content="Some({ post: Some(Drive), leaving: false, active: false })",
  )
  // Ann works all the next voyage at the post they kept, but never acts.
  let s = depart(s)
  debug_inspect(
    crossing_of(s).hands.get("ann").map(h => h.post),
    content="Some(Drive)",
  )
  let s = act(s, "bo", Watched(ticks=@core.HOUR))
  let s = dock(s)
  assert_eq(s.officers.keys().collect(), ["bo"])
}

///|
test "an officer leaving after the voyage is discharged at the dock" {
  let s = depart(in_port())
  let s = act(s, "ann", Posted(post=Drive))
  let s = act(s, "bo", Posted(post=Drive))
  let s = act(s, "ann", Leaving(leaving=true))
  let s = act(s, "bo", Leaving(leaving=true))
  let s = act(s, "bo", Leaving(leaving=false))
  debug_inspect(s.officers.get("ann").map(o => o.leaving), content="Some(true)")
  inspect(crossing_of(s).hands.contains("ann"), content="true")
  let s = dock(s)
  assert_eq(s.officers.keys().collect(), ["bo"])
}

///|
test "leaving in port is leaving at once" {
  let s = act(in_port(), "ann", Signed)
  let s = act(s, "ann", Leaving(leaving=true))
  inspect(s.officers.contains("ann"), content="false")
}

///|
test "only an officer aboard can stand down or leave in port" {
  let reject = (event : @core.Event) => {
    try in_port().apply(event) catch {
      err => err
    } noraise {
      _ => fail("expected a rejection")
    }
  }
  debug_inspect(
    reject(Crew(crew="ann", intent=Left)),
    content=(
      #|NotSigned(crew="ann")
    ),
  )
  debug_inspect(
    reject(Crew(crew="ann", intent=Leaving(leaving=true))),
    content=(
      #|NotSigned(crew="ann")
    ),
  )
  debug_inspect(
    reject(Crew(crew="ann", intent=Made)),
    content=(
      #|NotUnderway(event=Crew(crew="ann", intent=Made))
    ),
  )
}

///|
test "signing on and discharge are told" {
  let (said, s) = told(in_port(), [
    Crew(crew="ann", intent=Signed),
    Crew(crew="ann", intent=Signed),
    Departed(plan=plan20()),
    Crew(crew="bo", intent=Posted(post=Drive)),
  ])
  debug_inspect(
    said,
    content=(
      #|[
      #|  Signed(crew="ann"),
      #|  Departed,
      #|  Signed(crew="bo"),
      #|  Took(crew="bo", post=Drive),
      #|]
    ),
  )
  let c = crossing_of(s)
  let arrived = s.apply(Tick(at=s.at + c.forecast().unwrap() - c.t)) catch {
    _ => panic()
  }
  let docked = arrived.apply(Docked(stores=0)) catch { _ => panic() }
  debug_inspect(
    @core.happenings(arrived, Docked(stores=0), docked),
    content=(
      #|[
      #|  Docked(
      #|    recruits=0,
      #|    landing={
      #|      leg: 0,
      #|      aboard: 53855,
      #|      works: 0,
      #|      plan: {
      #|        burn: 10779000000,
      #|        coast: 18838000000,
      #|        eta_rate: 1308460,
      #|        coast_rate: 760500,
      #|      },
      #|    },
      #|  ),
      #|]
    ),
  )
}

///|
test "an order for arrival fires at arrival and carries into port" {
  let s = depart(act(in_port(), "ann", Posted(post=Drive)))
  let s = act(s, "ann", Ordered(order=Some({ phase: Arrived, post: Hull, })))
  let s = dock(s)
  debug_inspect(
    s.officers.get("ann").map(o => o.post),
    content="Some(Some(Hull))",
  )
}
