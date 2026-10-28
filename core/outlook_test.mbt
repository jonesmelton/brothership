///|
/// Crew to ask a trend for: everyone aboard, one who left a tally, and a
/// stranger.
fn trend_crew(c : @core.Crossing) -> Array[String] {
  [..c.hands.keys(), ..c.tallies.keys(), "stranger"]
}

///|
fn tally_of(c : @core.Crossing, crew : String) -> @core.Tally {
  c.tallies
  .get(crew)
  .unwrap_or({
    drive: 0,
    hull: 0,
    craft: 0,
    regard: 0,
    work: 0,
    watches_stood: 0,
    watches_broken: 0,
  })
}

///|
fn grow(c : @core.Crossing, ticks : Int64) -> @core.Crossing {
  c.apply(Elapsed(ticks~)) catch {
    _ => panic()
  }
}

///|
test "law: per_hour is the floor of delta * 3600 / span" {
  let mut checked = 0
  @qc.quick_check_fn((input : (Int64, Int64)) => {
    let (d, s) = input
    let delta = fold64(d, 2_000_000_000_000_001L) - 1_000_000_000_000_000L
    let span = fold64(s, 3600L) + 1L
    let r = @math.per_hour(delta, span)
    checked += 1
    r * span <= delta * 3600L && delta * 3600L < (r + 1L) * span
  })
  assert_true(checked > 0)
}

///|
test "law: a trend's span is within an hour and before the next boundary" {
  let mut checked = 0
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], (Int32, Int32, Int32), Int32),
  ) => {
    let (steps, fit, hull) = input
    let c = drive_schedule(plan20(), any_ship(fit, hull), steps)
    guard c.arrived_at is None else { true }
    let t = c.trend("0")
    checked += 1
    1L <= t.span && t.span <= 3600L && t.span <= c.next_boundary()
  })
  assert_true(checked > 0)
}

///|
test "an arrived crossing has a flat trend" {
  let c = grow(crew([Drive, Hull, Craft]), 1_000_000L)
  assert_eq(c.phase, Arrived)
  assert_eq(c.trend("0"), { span: 3600, regard: 0, work: 0, hull: 0, refit: 0, })
}

///|
/// Rates hold until the next boundary: every stock moves the same amount
/// each tick, so `k` ticks change it by `k/span` of the change over `span`.
/// The change over `span` itself is not observable through `apply`, which
/// also settles the boundary (a watch's bonus, a missed demand's loss), and
/// that is not part of the rate. So the law is checked on the whole ticks
/// before the boundary, against the one-tick change. The hull is linear
/// there too, but its trend is the change after clamping at the span's end.
test "law: rates hold until the next boundary and the trend reports them" {
  let mut checked = 0
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], (Int32, Int32, Int32), Int32),
  ) => {
    let (steps, fit, hull) = input
    let c = drive_schedule(plan20(), any_ship(fit, hull), steps)
    guard c.arrived_at is None else { true }
    let span = c.trend("0").span
    guard span >= 2L else { true }
    let one = grow(c, 1L)
    let mid = grow(c, span / 2L)
    let last = grow(c, span - 1L)
    let mut ok = true
    for who in trend_crew(c) {
      let t = c.trend(who)
      let b = tally_of(c, who)
      let d1 = (x : @core.Tally, y : @core.Tally) => {
        (y.regard - x.regard, y.work - x.work)
      }
      let (r1, w1) = d1(b, tally_of(one, who))
      let (rm, wm) = d1(b, tally_of(mid, who))
      let (rl, wl) = d1(b, tally_of(last, who))
      ok = ok &&
        rm == r1 * (span / 2L) &&
        wm == w1 * (span / 2L) &&
        rl == r1 * (span - 1L) &&
        wl == w1 * (span - 1L) &&
        t.regard == r1 * 3600L &&
        t.work == w1 * 3600L
    }
    let h1 = one.hull - c.hull
    let p1 = one.fit.progress - c.fit.progress
    let t = c.trend("0")
    // The last tick of the span may overshoot the hull's edge (full, or
    // empty) by part of a tick's change, which `flow` clamps: the hull
    // rate is the clamped change over the span, not `h1` per tick.
    let end = (c.hull + h1 * span).max(0L).min(@core.HULL_FULL)
    checked += 1
    ok &&
    mid.hull - c.hull == h1 * (span / 2L) &&
    last.hull - c.hull == h1 * (span - 1L) &&
    mid.fit.progress - c.fit.progress == p1 * (span / 2L) &&
    last.fit.progress - c.fit.progress == p1 * (span - 1L) &&
    t.hull == @math.per_hour(end - c.hull, span) &&
    t.refit == p1 * 3600L
  })
  assert_true(checked > 0)
}

///|
test "law: outcomes agree with the projection" {
  let mut checked = 0
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], (Int32, Int32, Int32), Int32),
  ) => {
    let (steps, fit, hull) = input
    let c = drive_schedule(plan20(), any_ship(fit, hull), steps)
    guard (c.outcomes(), c.project()) is (Some(out), Some(p)) else {
      c.outcomes() is None && c.project() is None
    }
    checked += 1
    out.length() == c.demands.length() &&
    out.mapi((i, o) => o.status == p.demands[i].status) == out.map(_ => true) &&
    out.all(o => {
      o.at >= c.t &&
      o.short >= 0L &&
      (o.status == Met) == (o.short == 0L || o.status == Met)
    })
  })
  assert_true(checked > 0)
}

///|
test "law: outcomes are exact" {
  let mut open = 0
  let mut closed = 0
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], (Int32, Int32, Int32), Int32),
  ) => {
    let (steps, fit, hull) = input
    let c = drive_schedule(plan20(), any_ship(fit, hull), steps)
    guard c.outcomes() is Some(out) else { true }
    let mut ok = true
    for i, o in out {
      let d = c.demands[i]
      if d.status is (Met | Missed) {
        closed += 1
        ok = ok &&
          o.status == d.status &&
          o.at == c.t &&
          o.short ==
          (if d.status == Met { 0L } else { (d.need - d.done).max(0L) })
        continue
      }
      open += 1
      let gap = o.at - c.t
      let on = grow(c, gap)
      let od = on.demands[i]
      ok = ok &&
        gap >= 1L &&
        od.status == o.status &&
        o.short == (if o.status == Met { 0L } else { od.need - od.done })
      if gap > 1L {
        ok = ok && grow(c, gap - 1L).demands[i].status is (Waiting | Open)
      }
    }
    ok
  })
  assert_true(open > 0)
  assert_true(closed > 0)
}

///|
test "outcomes of a fresh crossing" {
  let c = crew([Drive, Drive, Hull, Craft])
  let out = c.outcomes().unwrap()
  assert_eq(out.length(), c.demands.length())
  let p = c.project().unwrap()
  for i, o in out {
    assert_eq(o.status, p.demands[i].status)
    assert_true(o.at > 0L && o.at <= p.arrived_at.unwrap())
  }
}
