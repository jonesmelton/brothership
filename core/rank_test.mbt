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
test "the rank table and the floor agree" {
  assert_eq(@core.rank_thresholds, [0L, 40L, 120L, 280L, 500L])
  assert_eq(@core.COMMANDER, @core.rank_thresholds.length().to_int64() - 1L)
  for i, at in @core.rank_thresholds {
    let i = i.to_int64()
    assert_eq(@core.rank_floor(at * @core.REGARD_HOUR), i)
    if i > 0L {
      assert_eq(@core.rank_floor(at * @core.REGARD_HOUR - 1L), i - 1L)
    }
  }
  assert_eq(@core.rank_floor(9_000_000_000_000L), @core.COMMANDER)
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
test "a promotion is one step, at arrival, for someone aboard" {
  let sea = crew([Drive])
  debug_inspect(
    refuse(sea, Promoted(crew="0", rank=1L)),
    content="BadPromotion(crew=\"0\", rank=1)",
  )
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
      },
    },
  }
  let c = arrived(old, ["0"])
  let c = c.apply(Promoted(crew="0", rank=1L)) catch { _ => panic() }
  let c = { ..c, tallies: c.tallies.copy(), }
  c.tallies["gone"] = c.tallies.get("0").unwrap()
  let docked = c.dock().unwrap()
  assert_eq(docked.records.get("0").unwrap().rank, Some(1L))
  assert_eq(docked.records.get("gone").unwrap().rank, Some(1L))
  let next = @core.Crossing::new(plan20(), docked).apply(
    Posted(crew="0", post=Drive),
  ) catch {
    _ => panic()
  }
  assert_eq(next.hands.get("0").unwrap().rank, 1L)
}

///|
test "an old record without a rank decodes and falls back to its floor" {
  let json : Json = { "regard": "144000000", "works": "1", "carry": "0" }
  let r : @core.Record = @json.from_json(json)
  assert_eq(r.rank, None)
  let ship : @core.Ship = { ..ship(), records: { "a": r }, }
  assert_eq(ship.rank("a"), @core.rank_floor(r.regard))
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
