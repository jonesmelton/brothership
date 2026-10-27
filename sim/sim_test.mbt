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
fn inside(plan : @core.Plan, at : Int64) -> Bool {
  plan.fastest() <= at && at <= plan.slowest()
}

///|
test "every scenario on every ship arrives inside the envelope" {
  let mut checked = 0
  for p in @sim.profiles() {
    for s in @sim.scenarios() {
      let s = { ..s, ship: p, route: p.route, }
      let plan = s.route.plan()
      // Crews checking in every minute are slow to fly and vary little.
      let runs = if s.name.contains("every minute") { 1 } else { 4 }
      for o in s.batch(runs~) {
        assert_true(
          inside(plan, o.arrived_at),
          msg="\{p.name}, \{s.name} seed \{o.seed}: \{o.arrived_at}",
        )
        assert_true(0L <= o.min_hull && o.end_hull <= @core.HULL_FULL)
        checked += 1
      }
    }
  }
  inspect(checked, content="88")
}

///|
test "every policy, checking in every minute, stays inside the envelope" {
  for distance in [2.0, 5.0, 20.0, 60.0] {
    for policy in @sim.policies {
      let s : @sim.Scenario = {
        name: "sweep",
        ship: @sim.profiles()[2],
        route: { ..@sim.profiles()[2].route, distance_ly: distance, },
        hull: @core.HULL_FULL / 2L,
        actors: Array::makei(4, i => {
          name: "x\{i}",
          policy,
          craft: if i % 2 == 0 {
            Artist
          } else {
            Engineer
          },
          cadence: Every(every=600L, jitter=300L),
          joins_at: 0L,
        }),
      }
      let o = s.run(distance.to_int64()).outcome()
      assert_true(
        inside(s.route.plan(), o.arrived_at),
        msg="\{distance} ly \{policy.name()}",
      )
    }
  }
}

///|
/// A careful crew member who changed post at every band edge would make a
/// boundary every few ticks, and a crossing would take thousands of steps.
test "no scripted crew chatters between posts" {
  for p in @sim.profiles() {
    for s in @sim.scenarios() {
      let s = { ..s, ship: p, route: p.route, }
      let r = s.run(5)
      let hours = r.arrived_at / @core.HOUR + 1L
      let changes = r.decisions.filter(d => d.from is Some(f) && f != d.to)
      let players = s.actors.filter(a => a.is_player()).length().max(1)
      // Hammering scenarios check in every minute, on purpose.
      let bound = if s.name.contains("every minute") { 120L } else { 6L }
      assert_true(
        changes.length().to_int64() <=
        bound * hours * (s.actors.length() + players).to_int64(),
        msg="\{p.name}, \{s.name}: \{changes.length()} changes in \{hours} h",
      )
      assert_true(r.samples.length() < 2000, msg="\{p.name}, \{s.name}")
    }
  }
}

///|
test "a voyage carries refits, recruits, records and hull from leg to leg" {
  let legs : Array[Double] = [8.0, 20.0, 12.0, 30.0, 8.0]
  let mut checked = 0
  for p in @sim.profiles() {
    for craft in [@core.Artist, @core.Engineer] {
      let base = @sim.scenarios()[0]
      let actors = base.actors.copy()
      actors[0] = { ..actors[0], policy: Selfish, craft, }
      let s = { ..base, ship: p, route: p.route, actors, }
      let voyage = s.voyage(legs, 3)
      let mut prev = s.departing(3)
      for i, leg in voyage {
        let r = leg.run
        let next = leg.docked
        assert_true(inside(r.plan, r.arrived_at), msg="\{p.name} leg \{i}")
        // A crossing is a few dozen instants of interest. Thousands mean a
        // ship and its crew are chasing each other between posts.
        assert_true(r.samples.length() < 200, msg="\{p.name} leg \{i}")
        assert_eq(next.crossings, prev.crossings + 1L)
        assert_true(next.recruits >= prev.recruits)
        assert_true(next.fit.needed <= prev.fit.needed)
        assert_true(next.fit.coils >= prev.fit.coils)
        for crew, was in prev.records {
          let now = next.records.get(crew).unwrap()
          assert_true(now.works >= was.works && now.regard >= was.regard)
        }
        // Recruits work ship posts only, so they make no works.
        for crew, t in r.last.tallies {
          if crew >= 1000 {
            assert_eq(t.craft, 0L)
          }
        }
        prev = next
        checked += 1
      }
    }
  }
  inspect(checked, content="40")
}

///|
/// The map's hops run 8 to 30 ly. Shorter hops break the spread limit once
/// coils are fitted, because more of the crossing is burn.
test "every ship's envelopes meet the design's targets across the map" {
  let mut checked = 0
  for p in @sim.profiles() {
    for coils in 0L..<=@core.MAX_LEVEL {
      for d in [8.0, 12.0, 20.0, 30.0] {
        let plan = { ..p.route, distance_ly: d, }.plan_with(coils~)
        let label = "\{p.name}, \{d} ly, coils \{coils}"
        assert_true(plan.fastest() >= 5L * @core.HOUR, msg=label)
        assert_true(plan.slowest() <= 30L * @core.HOUR, msg=label)
        assert_true(plan.slowest() * 10L <= plan.fastest() * 25L, msg=label)
        checked += 1
      }
    }
  }
  inspect(checked, content="64")
}

///|
test "ships differ, and so do players" {
  let base = @sim.scenarios()[0]
  let median = (s : @sim.Scenario) => {
    @sim.percentile(s.batch(runs=5).map(o => o.arrived_at), 50)
  }
  let by_ship = @sim.profiles().map(p => {
    median({ ..base, ship: p, route: p.route, })
  })
  let fastest = by_ship.fold(init=@math.MAX_TICKS, (m, x) => m.min(x))
  let slowest = by_ship.fold(init=0L, (m, x) => m.max(x))
  // The same crew arrives at least a tenth sooner on the quickest ship.
  assert_true(slowest * 10L >= fastest * 11L)
  let with_policy = (policy : @sim.Policy) => {
    let actors = base.actors.copy()
    actors[0] = { ..actors[0], policy, }
    { ..base, actors, }
  }
  let own = (s : @sim.Scenario) => {
    s.batch(runs=5).fold(init=0L, (n, o) => n + o.work)
  }
  // Craft or drive is a real trade: one is sooner, the other makes more.
  assert_true(median(with_policy(Driver)) < median(with_policy(Selfish)))
  assert_true(own(with_policy(Selfish)) > own(with_policy(Driver)))
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
