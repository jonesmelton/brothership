///|
/// 20 ly at 40,000 g, γ cap 24,000: about 11.5 hours at full burn.
fn plan20() -> @core.Plan {
  {
    burn: 10_779_000_000,
    coast: 18_838_000_000,
    eta_rate: 1_308_460,
    coast_rate: 760_500,
    drive_needed: 4,
    wear: 30_000,
    repair: 28_000,
  }
}

///|
/// A short hop that never reaches its cap: all burn and approach.
fn plan_short() -> @core.Plan {
  { ..plan20(), burn: 8_000_000_000, coast: 0, }
}

///|
fn crew(posts : Array[@core.Post]) -> @core.Crossing {
  let mut c = @core.Crossing::new(plan20(), hull=@core.HULL_FULL)
  for i, post in posts {
    c = c.apply(Posted(crew=i, post~)) catch { _ => panic() }
  }
  c
}

///|
/// `x` folded into `[0, m)`, safe for every input including the minimum.
fn fold64(x : Int64, m : Int64) -> Int64 {
  (x % m + m) % m
}

///|
fn post_of(n : Int32) -> @core.Post {
  match (n % 3 + 3) % 3 {
    0 => Drive
    1 => Hull
    _ => Craft
  }
}

///|
/// A crossing driven by an arbitrary schedule of post changes. Each step is
/// (crew slot, post choice, ticks to wait first).
fn drive_schedule(
  plan : @core.Plan,
  hull : Int64,
  steps : Array[(Int32, Int32, Int64)],
) -> @core.Crossing {
  let mut c = @core.Crossing::new(plan, hull~)
  for step in steps {
    let (slot, choice, wait) = step
    let wait = fold64(wait, 7200L) + 1L
    c = c.apply(Elapsed(ticks=wait)) catch { _ => c }
    c = c.apply(Posted(crew=(slot % 12 + 12) % 12, post=post_of(choice))) catch {
      _ => c
    }
  }
  c
}

///|
fn arrival(c : @core.Crossing) -> Int64 {
  c.forecast().unwrap()
}

///|
test "nobody aboard the drive still arrives, at the slowest forecast" {
  let c = @core.Crossing::new(plan20(), hull=@core.HULL_FULL)
  inspect(arrival(c) == plan20().slowest(), content="true")
  let all_drive = crew([Drive, Drive, Drive, Drive])
  inspect(arrival(all_drive) >= plan20().fastest(), content="true")
  inspect(arrival(all_drive) < arrival(c), content="true")
}

///|
test "the envelope for the 20 ly plan, in minutes" {
  debug_inspect(
    (plan20().fastest() / 60L, plan20().slowest() / 60L),
    content=(
      #|(687, 1197)
    ),
  )
}

///|
test "phases run burn, coast, approach, arrived" {
  let mut c = crew([Drive, Drive, Drive, Drive])
  let seen = [c.phase]
  while c.phase != Arrived {
    c = c.apply(Elapsed(ticks=c.next_boundary())) catch { _ => panic() }
    if seen.last() != Some(c.phase) {
      seen.push(c.phase)
    }
  }
  debug_inspect(seen, content="[Burn, Coast, Approach, Arrived]")
}

///|
test "no coast goes straight from burn to approach" {
  let mut c = @core.Crossing::new(plan_short(), hull=@core.HULL_FULL)
  c = c.apply(Elapsed(ticks=c.next_boundary())) catch { _ => panic() }
  debug_inspect(c.phase, content="Approach")
}

///|
test "rejections" {
  let c = @core.Crossing::new(plan20(), hull=@core.HULL_FULL)
  let reject = (event : @core.CrossingEvent) => {
    try c.apply(event) catch {
      err => err
    } noraise {
      _ => fail("expected a rejection")
    }
  }
  debug_inspect(reject(Elapsed(ticks=0)), content="BadTicks(ticks=0)")
  debug_inspect(
    reject(Elapsed(ticks=@math.MAX_TICKS + 1)),
    content="BadTicks(ticks=1000000001)",
  )
  debug_inspect(reject(Left(crew=3)), content="NotAboard(crew=3)")
}

///|
test "law: one long gap equals two short ones" {
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Int64, Int64)) => {
    let (steps, a, b) = input
    let a = fold64(a, 100_000L) + 1L
    let b = fold64(b, 100_000L) + 1L
    let c = drive_schedule(plan20(), @core.HULL_FULL / 3, steps)
    let whole = c.apply(Elapsed(ticks=a + b)) catch { _ => panic() }
    let split = (c.apply(Elapsed(ticks=a)) catch { _ => panic() }).apply(
      Elapsed(ticks=b),
    ) catch {
      _ => panic()
    }
    whole == split
  })
}

///|
test "law: no schedule of posts leaves the envelope" {
  let mut checked = 0
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Bool, Int32)) => {
    let (steps, short, hull) = input
    let plan = if short { plan_short() } else { plan20() }
    let hull = fold64(hull.to_int64() * 1000L, @core.HULL_FULL + 1L)
    let c = drive_schedule(plan, hull, steps)
    let at = match c.arrived_at {
      Some(at) => at
      None => arrival(c)
    }
    checked += 1
    plan.fastest() <= at && at <= plan.slowest()
  })
  assert_true(checked > 0)
}

///|
test "law: hull stays within bounds" {
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Int32)) => {
    let (steps, hull) = input
    let hull = fold64(hull.to_int64() * 1000L, @core.HULL_FULL + 1L)
    let c = drive_schedule(plan20(), hull, steps)
    0L <= c.hull && c.hull <= @core.HULL_FULL
  })
}

///|
test "law: another hand on the drive never delays arrival" {
  let mut checked = 0
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Int32)) => {
    let (steps, slot) = input
    let c = drive_schedule(plan20(), @core.HULL_FULL, steps)
    guard c.phase != Arrived else { true }
    let slot = 100 + (slot % 8 + 8) % 8
    let more = c.apply(Posted(crew=slot, post=Drive)) catch { _ => panic() }
    // A hand taken from the hull may cost a band later; compare like with
    // like by adding a new hand rather than moving one.
    checked += 1
    arrival(more) <= arrival(c)
  })
  assert_true(checked > 0)
}

///|
test "exhaustive: the setting is monotone in drive crew and within bounds" {
  let mut checked = 0
  for needed in 1L..<=64L {
    for cap in [350L, 512L, 675L, 837L, 1000L] {
      let mut last = @math.SETTING_FLOOR
      for drive in 0L..<=64L {
        let s = @math.setting(drive, needed, cap)
        assert_true(s >= last && s >= @math.SETTING_FLOOR && s <= cap)
        last = s
        checked += 1
      }
    }
  }
  inspect(checked, content="20800")
}
