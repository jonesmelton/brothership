///|
test "the default route plans to the closed form" {
  let plan = @sim.Route::default().plan()
  debug_inspect(
    plan,
    content=(
      #|{
      #|  burn: 10778956289,
      #|  coast: 18837595660,
      #|  eta_rate: 1308465,
      #|  coast_rate: 760514,
      #|  drive_needed: 4,
      #|  wear: 30000,
      #|  repair: 28000,
      #|}
    ),
  )
}

///|
test "a run replays exactly from its seed" {
  let s = @sim.scenarios()[1]
  assert_eq(s.run(7), s.run(7))
  assert_true(s.run(7).outcome() != s.run(8).outcome())
}

///|
test "every scenario arrives inside the envelope, over many seeds" {
  let mut checked = 0
  for s in @sim.scenarios() {
    let plan = s.route.plan()
    for o in s.batch(runs=40) {
      assert_true(
        plan.fastest() <= o.arrived_at && o.arrived_at <= plan.slowest(),
        msg="\{s.name} seed \{o.seed}: \{o.arrived_at}",
      )
      assert_true(0L <= o.min_hull && o.end_hull <= @core.HULL_FULL)
      checked += 1
    }
  }
  inspect(checked, content="280")
}

///|
test "adversaries checking in every minute stay inside the envelope" {
  for distance in [2.0, 5.0, 20.0, 60.0, 150.0, 300.0] {
    for policy in [@sim.Hastener, @sim.Saboteur, @sim.Random] {
      let s : @sim.Scenario = {
        name: "sweep",
        route: { ..@sim.Route::default(), distance_ly: distance, },
        hull: @core.HULL_FULL / 2L,
        actors: Array::makei(6, i => {
          name: "x\{i}",
          policy,
          cadence: Every(every=60L, jitter=30L),
          joins_at: 0L,
        }),
      }
      let plan = s.route.plan()
      let o = s.run(distance.to_int64()).outcome()
      assert_true(
        plan.fastest() <= o.arrived_at && o.arrived_at <= plan.slowest(),
        msg="\{distance} ly \{policy.name()}",
      )
    }
  }
}

///|
test "percentile and histogram" {
  let xs : Array[Int64] = [5, 1, 4, 2, 3]
  debug_inspect(
    (@sim.percentile(xs, 50), @sim.percentile(xs, 100)),
    content="(3, 5)",
  )
  debug_inspect(@sim.histogram(xs, lo=1, hi=5, bins=2), content="[2, 3]")
}
