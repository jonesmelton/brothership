///|
/// An arrived crossing with one hand per `(id, rank, hours)`, who has served
/// `hours` aboard.
fn bench(crew : Array[(String, Int64, Int64)]) -> @core.Crossing {
  let p = @ships.profiles()[1]
  let c = @core.Crossing::new(p.next_plan(legs=0, coils=0), p.ship(seed=1))
  let hands : Map[String, @core.Hand] = Map([])
  let records : Map[String, @core.Record] = Map([])
  for entry in crew {
    let (id, rank, hours) = entry
    hands[id] = {
      post: @core.Post::Drive,
      craft: @core.Craft::Artist,
      rank,
      watch: None,
      order: None,
    }
    records[id] = {
      regard: 0,
      works: 0,
      carry: 0,
      rank: Some(rank),
      served: hours * @core.HOUR,
    }
  }
  { ..c, phase: Arrived, hands, ship: { ..c.ship, records, }, }
}

///|
fn everyone(_ : String) -> Bool {
  true
}

///|
test "an ensign is eligible after ENSIGN_SERVICE, anyone above at once" {
  let c = bench([("new", 0, 5), ("old", 0, 6), ("lt", 1, 0)])
  debug_inspect(
    ["new", "old", "lt", "ghost"].map(id => @ships.eligible(c, id)),
    content="[false, true, true, false]",
  )
}

///|
test "the ship may promote as many as it likes, one step each, to commander" {
  let c = bench([("a", 4, 50), ("b", 3, 50), ("c", 3, 50), ("d", 0, 1)])
  debug_inspect(
    @ships.allowed(c, ["a", "b", "c", "d", "b", "ghost"], officer=everyone),
    content=(
      #|[("b", 4), ("c", 4)]
    ),
  )
  debug_inspect(@ships.allowed(c, ["b"], officer=id => id != "b"), content="[]")
}

///|
test "by script, arrival promotes the longest-serving officer it may" {
  let c = bench([("a", 0, 7), ("b", 2, 30), ("c", 0, 2), ("d", 4, 99)])
  debug_inspect(
    @ships.promotions(c, officer=everyone),
    content=(
      #|[("b", 3)]
    ),
  )
  let tie = bench([("y", 0, 7), ("x", 0, 7)])
  debug_inspect(
    @ships.promotions(tie, officer=everyone),
    content=(
      #|[("x", 1)]
    ),
  )
  debug_inspect(
    @ships.promotions({ ..c, phase: Coast, }, officer=everyone),
    content="[]",
  )
}

///|
test "a crew three in four ensigns, one of them eligible, is bottom-heavy" {
  let heavy = bench([("a", 0, 7), ("b", 0, 1), ("c", 0, 1), ("d", 2, 9)])
  inspect(@ships.bottom_heavy(heavy, officer=everyone), content="true")
  debug_inspect(
    @ships.first_ensign(heavy, officer=everyone),
    content=(
      #|[("a", 1)]
    ),
  )
  let green = bench([("a", 0, 1), ("b", 0, 1)])
  inspect(@ships.bottom_heavy(green, officer=everyone), content="false")
  let mixed = bench([("a", 0, 7), ("b", 0, 7), ("c", 1, 9), ("d", 2, 9)])
  inspect(@ships.bottom_heavy(mixed, officer=everyone), content="false")
  let alone = bench([("a", 0, 7)])
  inspect(@ships.bottom_heavy(alone, officer=everyone), content="false")
}

///|
test "the clock promotes before it docks, in one batch" {
  let p = @ships.profiles()[1]
  let ship = p.ship(seed=1)
  let ship : @core.Ship = {
    ..ship,
    records: {
      "a": {
        regard: 200L * @core.REGARD_HOUR,
        works: 0,
        carry: 0,
        rank: Some(0L),
        served: @ships.ENSIGN_SERVICE,
      },
    },
  }
  let mut s = @core.State::initial(ship, profile=p.name)
  let mut now = 1_800_000_000L
  while !(s.leg is Underway(..)) {
    let (_, next) = p.due(s, now, officer=everyone)
    s = next
    now = p.wake(s).max(now + 1L)
  }
  s = s.apply(Crew(crew="a", intent=Posted(post=Drive))) catch { _ => panic() }
  let mut batch = []
  for _ in 0..<1000 {
    now = p.wake(s).max(now + 1L)
    let (events, next) = p.due(s, now, officer=everyone)
    s = next
    if events.contains(Docked) {
      batch = events
      break
    }
  }
  let at = batch.search(Docked).unwrap()
  guard batch[at - 1] is Promoted(crew="a", rank=1) else {
    fail("expected a promotion just before Docked")
  }
  assert_eq(s.ship.records.get("a").unwrap().rank, Some(1L))
}
