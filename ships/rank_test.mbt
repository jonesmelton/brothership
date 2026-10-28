///|
/// An arrived crossing with one hand per `(id, rank, regard)`, whose total
/// regard (record plus tally) is `regard` hours.
fn bench(crew : Array[(String, Int64, Int64)]) -> @core.Crossing {
  let p = @ships.profiles()[1]
  let c = @core.Crossing::new(p.next_plan(legs=0, coils=0), p.ship(seed=1))
  let hands : Map[String, @core.Hand] = Map([])
  let tallies : Map[String, @core.Tally] = Map([])
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
    tallies[id] = {
      drive: 0,
      hull: 0,
      craft: 0,
      regard: hours * @core.REGARD_HOUR,
      work: 0,
      watches_stood: 0,
      watches_broken: 0,
    }
    records[id] = { regard: 0, works: 0, carry: 0, rank: Some(rank), }
  }
  { ..c, phase: Arrived, hands, tallies, ship: { ..c.ship, records, }, }
}

///|
fn everyone(_ : String) -> Bool {
  true
}

///|
test "rank caps are one table, uncapped at ensign" {
  debug_inspect(
    @ships.rank_caps(10L),
    content="[None, Some(4), Some(3), Some(2), Some(1)]",
  )
}

///|
test "a solo officer climbs one step per arrival" {
  let c = bench([("a", 0L, 600L)])
  debug_inspect(@ships.promotions(c, officer=everyone), content="[(\"a\", 1)]")
  let c = bench([("a", 3L, 600L)])
  debug_inspect(@ships.promotions(c, officer=everyone), content="[(\"a\", 4)]")
}

///|
test "nobody is promoted past commander, demoted, or without the regard" {
  debug_inspect(
    @ships.promotions(
      bench([("a", 4L, 9000L), ("b", 2L, 0L), ("c", 3L, 100L)]),
      officer=everyone,
    ),
    content="[]",
  )
}

///|
test "a crossing that has not arrived promotes nobody" {
  let c = { ..bench([("a", 0L, 600L)]), phase: Burn, }
  debug_inspect(@ships.promotions(c, officer=everyone), content="[]")
}

///|
test "the officer predicate excludes everyone else" {
  let c = bench([("a", 0L, 600L), ("b", 0L, 600L)])
  debug_inspect(
    @ships.promotions(c, officer=id => id == "b"),
    content="[(\"b\", 1)]",
  )
}

///|
test "regard decides who takes the last place, then crew id" {
  let c = bench([("a", 3L, 300L), ("b", 3L, 600L), ("c", 3L, 600L)])
  debug_inspect(@ships.promotions(c, officer=everyone), content="[(\"b\", 4)]")
  let tie = bench([("z", 0L, 100L), ("m", 0L, 100L), ("a", 0L, 100L)])
  debug_inspect(
    @ships.promotions(tie, officer=everyone),
    content="[(\"a\", 1), (\"m\", 1), (\"z\", 1)]",
  )
}

///|
test "a promotion frees the rank it leaves for the next in line" {
  let c = bench([("a", 3L, 600L), ("b", 2L, 300L)])
  debug_inspect(
    @ships.promotions(c, officer=everyone),
    content="[(\"a\", 4), (\"b\", 3)]",
  )
}

///|
test "a topheavy ship promotes nobody into a full rank but fills lower ones" {
  let c = bench([
    ("a", 4L, 600L),
    ("b", 3L, 600L),
    ("c", 3L, 400L),
    ("d", 2L, 300L),
    ("e", 2L, 300L),
    ("f", 2L, 300L),
    ("g", 0L, 130L),
  ])
  debug_inspect(@ships.promotions(c, officer=everyone), content="[(\"g\", 1)]")
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
