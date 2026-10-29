///|
fn arrived(ship : @core.Ship, crew : Array[String]) -> @core.Crossing {
  let mut c = @core.Crossing::new(plan20(), ship)
  for id in crew {
    c = c.apply(Posted(crew=id, post=Drive)) catch { _ => panic() }
  }
  c.project().unwrap()
}

///|
fn refuse(
  c : @core.Crossing,
  e : @core.CrossingEvent,
) -> @core.CrossingRejected {
  try c.apply(e) catch {
    err => err
  } noraise {
    _ => abort("expected a rejection")
  }
}

///|
test "served counts each tick a hand holds a post, and docking keeps it" {
  let c = crew([Drive, Craft])
  let c = c.apply(Elapsed(ticks=@core.HOUR)) catch { _ => panic() }
  assert_eq(c.served("0"), @core.HOUR)
  assert_eq(c.served("1"), @core.HOUR)
  assert_eq(c.served("nobody"), 0L)
  let docked = c.project().unwrap().dock().unwrap()
  let r = docked.records.get("0").unwrap()
  assert_true(r.served > @core.HOUR)
  let next = @core.Crossing::new(plan20(), docked)
  assert_eq(next.served("0"), r.served)
}

///|
test "a watch is at least an hour and has no upper bound" {
  let c = crew([Drive])
  let long = c.apply(Watched(crew="0", ticks=13L * @core.HOUR)) catch {
    _ => panic()
  }
  assert_eq(long.hands.get("0").unwrap().watch.unwrap().until, 13L * @core.HOUR)
  debug_inspect(
    refuse(c, Watched(crew="0", ticks=@core.HOUR - 1L)),
    content="BadWatch(ticks=3599)",
  )
}

///|
test "a promotion is one step, at any phase, for someone aboard" {
  let sea = crew([Drive])
  let promoted = sea.apply(Promoted(crew="0", rank=1L)) catch { _ => panic() }
  assert_eq(promoted.hands.get("0").unwrap().rank, 1L)
  let c = arrived(ship(), ["0"])
  debug_inspect(
    refuse(c, Promoted(crew="9", rank=1L)),
    content="NotAboard(crew=\"9\")",
  )
  debug_inspect(
    refuse(c, Promoted(crew="0", rank=2L)),
    content="BadPromotion(crew=\"0\", rank=2)",
  )
  debug_inspect(
    refuse(c, Promoted(crew="0", rank=0L)),
    content="BadPromotion(crew=\"0\", rank=0)",
  )
  let c = c.apply(Promoted(crew="0", rank=1L)) catch { _ => panic() }
  assert_eq(c.hands.get("0").unwrap().rank, 1L)
  let mut c = c
  for r in 2L..<=@core.COMMANDER {
    c = c.apply(Promoted(crew="0", rank=r)) catch { _ => panic() }
  }
  debug_inspect(
    refuse(c, Promoted(crew="0", rank=5L)),
    content="BadPromotion(crew=\"0\", rank=5)",
  )
}

///|
test "docking writes the rank of everyone with a tally" {
  let old : @core.Ship = {
    ..ship(),
    records: {
      "gone": {
        regard: 50L * @core.REGARD_HOUR,
        works: 0,
        carry: 0,
        rank: None,
        served: 0,
      },
    },
  }
  let c = arrived(old, ["0"])
  let c = c.apply(Promoted(crew="0", rank=1L)) catch { _ => panic() }
  let c = { ..c, tallies: c.tallies.copy(), }
  c.tallies["gone"] = c.tallies.get("0").unwrap()
  let docked = c.dock().unwrap()
  assert_eq(docked.records.get("0").unwrap().rank, Some(1L))
  assert_eq(docked.records.get("gone").unwrap().rank, Some(0L))
  let next = @core.Crossing::new(plan20(), docked).apply(
    Posted(crew="0", post=Drive),
  ) catch {
    _ => panic()
  }
  assert_eq(next.hands.get("0").unwrap().rank, 1L)
}

///|
test "a record without a rank is an ensign's" {
  let json : Json = {
    "regard": "144000000",
    "works": "1",
    "carry": "0",
    "served": "0",
  }
  let r : @core.Record = @json.from_json(json)
  assert_eq(r.rank, None)
  let ship : @core.Ship = { ..ship(), records: { "a": r }, }
  assert_eq(ship.rank("a"), @core.ENSIGN)
  assert_eq(ship.rank("nobody"), @core.ENSIGN)
  let explicit = { ..r, rank: Some(0L), }
  assert_eq({ ..ship, records: { "a": explicit }, }.rank("a"), 0L)
}

///|
test "a promotion is a happening" {
  let s = underway(plan20(), ship())
  let e : @core.Event = Promoted(crew="ann", rank=2L)
  debug_inspect(
    @core.happenings(s, e, s),
    content=(
      #|[
      #|  Promoted(
      #|    crew="ann",
      #|    rank=2,
      #|    tally={
      #|      drive: 0,
      #|      hull: 0,
      #|      craft: 0,
      #|      regard: 0,
      #|      work: 0,
      #|      watches_stood: 0,
      #|      watches_broken: 0,
      #|      served: 0,
      #|    },
      #|  ),
      #|]
    ),
  )
}

///|
test "a promotion carries the crossing's tally" {
  let s = underway(plan20(), ship())
  let s = s.apply(Crew(crew="ann", intent=Posted(post=Drive))) catch {
    _ => panic()
  }
  let s = s.apply(Tick(at=s.at + 3600L))
  let e : @core.Event = Promoted(crew="ann", rank=1L)
  match @core.happenings(s, e, s) {
    [Promoted(crew="ann", rank=1L, tally~)] => {
      assert_true(tally.drive > 0L)
      assert_eq(tally, s.crossing().unwrap().tallies.get("ann").unwrap())
    }
    _ => fail("expected one Promoted")
  }
}
