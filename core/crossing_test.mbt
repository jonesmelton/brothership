///|
/// 20 ly at 40,000 g, γ cap 24,000: about 11.5 hours at full burn.
fn plan20() -> @core.Plan {
  {
    burn: 10_779_000_000,
    coast: 18_838_000_000,
    eta_rate: 1_308_460,
    coast_rate: 760_500,
  }
}

///|
/// A short hop that never reaches its cap: all burn and approach.
fn plan_short() -> @core.Plan {
  { ..plan20(), burn: 8_000_000_000, coast: 0, }
}

///|
let values : @core.Values = { drive: 2, hull: 2, craft: 1, }

///|
fn ship(hull~ : Int64 = @core.HULL_FULL, seed~ : Int64 = 1L) -> @core.Ship {
  {
    ..@core.Ship::new(
      values,
      @core.Fit::new(needed=4, wear=30_000, repair=28_000),
      seed~,
    ),
    hull,
  }
}

///|
fn crew(posts : Array[@core.Post]) -> @core.Crossing {
  let mut c = @core.Crossing::new(plan20(), ship())
  for i, post in posts {
    c = c.apply(Posted(crew=i.to_string(), post~)) catch { _ => panic() }
  }
  c
}

///|
/// `x` folded into `[0, m)`, safe for every input including the minimum.
fn fold64(x : Int64, m : Int64) -> Int64 {
  (x % m + m) % m
}

///|
fn fold(x : Int32, m : Int32) -> Int32 {
  (x % m + m) % m
}

///|
fn post_of(n : Int32) -> @core.Post {
  let posts : Array[@core.Post] = [Drive, Hull, Craft]
  posts[fold(n, 3)]
}

///|
/// Any event but `Elapsed`, chosen by `kind`, for crew slot `slot`.
fn event_of(kind : Int32, slot : Int32, arg : Int64) -> @core.CrossingEvent {
  let crew = fold(slot, 12).to_string()
  match fold(kind, 11) {
    0 | 1 | 2 | 3 => Posted(crew~, post=post_of(arg.to_int()))
    10 => {
      let phases : Array[@core.Phase] = [Coast, Approach, Burn]
      Ordered(
        crew~,
        order=if arg % 5L == 0L {
          None
        } else {
          Some({ phase: phases[fold64(arg, 3L).to_int()], post: post_of(slot), })
        },
      )
    }
    4 => Left(crew~)
    5 => Crafted(crew~, craft=if arg % 2L == 0L { Engineer } else { Artist })
    6 | 7 => Watched(crew~, ticks=fold64(arg, 12L) * @core.HOUR + @core.HOUR)
    8 =>
      Refitting(
        refit=match fold64(arg, 4L) {
          0L => None
          i => Some(@core.refits[i.to_int() - 1])
        },
      )
    _ =>
      Asked(
        post=if arg % 4L == 0L { None } else { Some(post_of(arg.to_int())) },
      )
  }
}

///|
/// A crossing driven by an arbitrary schedule. Each step is (kind, crew
/// slot, argument): wait a little, then apply the event if it applies.
fn drive_schedule(
  plan : @core.Plan,
  ship : @core.Ship,
  steps : Array[(Int32, Int32, Int64)],
) -> @core.Crossing {
  let mut c = @core.Crossing::new(plan, ship)
  for step in steps {
    let (kind, slot, arg) = step
    let wait = fold64(arg, 5400L) + 1L
    c = c.apply(Elapsed(ticks=wait)) catch { _ => c }
    c = c.apply(event_of(kind, slot, arg)) catch { _ => c }
  }
  c
}

///|
fn arrival(c : @core.Crossing) -> Int64 {
  c.forecast().unwrap()
}

///|
/// A ship with any fit the content could give it: 2 to 8 drive hands,
/// wear up to 60,000 and repair up to 50,000 per tick.
fn any_ship(fit : (Int32, Int32, Int32), hull : Int32) -> @core.Ship {
  let (needed, wear, repair) = fit
  {
    ..ship(hull=hull_of(hull)),
    fit: @core.Fit::new(
      needed=2L + fold64(needed.to_int64(), 7L),
      wear=fold64(wear.to_int64(), 60_001L),
      repair=fold64(repair.to_int64(), 50_001L),
    ),
  }
}

///|
fn hull_of(h : Int32) -> Int64 {
  fold64(h.to_int64() * 1000L, @core.HULL_FULL + 1L)
}

///|
test "nobody aboard the drive still arrives, at the slowest forecast" {
  let c = @core.Crossing::new(plan20(), ship())
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
  let mut c = @core.Crossing::new(plan_short(), ship())
  while c.phase == Burn {
    c = c.apply(Elapsed(ticks=c.next_boundary())) catch { _ => panic() }
  }
  debug_inspect(c.phase, content="Approach")
}

///|
test "rejections" {
  let c = crew([Drive])
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
  debug_inspect(reject(Left(crew="3")), content="NotAboard(crew=\"3\")")
  debug_inspect(
    reject(Watched(crew="0", ticks=0L)),
    content="BadWatch(ticks=0)",
  )
  let watching = c.apply(Watched(crew="0", ticks=@core.HOUR)) catch {
    _ => panic()
  }
  debug_inspect(
    try watching.apply(Watched(crew="0", ticks=@core.HOUR)) catch {
      err => err
    } noraise {
      _ => fail("expected a rejection")
    },
    content="OnWatch(crew=\"0\")",
  )
  let maxed = { ..c, fit: { ..c.fit, needed: 2, injectors: 2, }, }
  debug_inspect(
    try maxed.apply(Refitting(refit=Some(Injectors))) catch {
      err => err
    } noraise {
      _ => fail("expected a rejection")
    },
    content="Unbuildable(refit=Injectors)",
  )
}

///|
test "demands are fixed by seed and crossing, whatever the crew do" {
  let a = @core.demands_for(plan20(), 7, 0)
  let b = @core.demands_for(plan20(), 7, 0)
  assert_eq(a, b)
  let mut kinds = 0
  for seed in 0L..<64L {
    let ds = @core.demands_for(plan20(), seed, 3)
    assert_true(ds.length() >= 1 && ds.length() <= 2)
    for d in ds {
      assert_true(d.need > 0L && d.opens_at > 0L)
      if d.hazard == Salvage {
        assert_true(d.phase == Coast)
        kinds = kinds | 1
      } else {
        assert_true(d.phase is (Burn | Approach))
        kinds = kinds | 2
      }
    }
    for d in @core.demands_for(plan_short(), seed, 3) {
      assert_true(d.hazard != Salvage)
    }
  }
  inspect(kinds, content="3")
}

///|
test "a watch stood to its end pays; one broken costs" {
  let c = crew([Hull]).apply(Watched(crew="0", ticks=@core.HOUR)) catch {
    _ => panic()
  }
  let stood = c.apply(Elapsed(ticks=@core.HOUR)) catch { _ => panic() }
  let t = stood.tallies.get("0").unwrap()
  debug_inspect(
    (t.watches_stood, stood.hands.get("0").unwrap().watch),
    content="(1, None)",
  )
  let broken = (c.apply(Elapsed(ticks=@core.HOUR / 2L)) catch { _ => panic() }).apply(
    Posted(crew="0", post=Drive),
  ) catch {
    _ => panic()
  }
  inspect(broken.tallies.get("0").unwrap().watches_broken, content="1")
}

///|
test "a standing order takes its post when the phase begins" {
  let c = crew([Craft, Craft]).apply(
    Ordered(crew="0", order=Some({ phase: Approach, post: Drive, })),
  ) catch {
    _ => panic()
  }
  let c = c.apply(Watched(crew="0", ticks=2L * @core.HOUR)) catch {
    _ => panic()
  }
  let mut c = c
  while c.phase != Approach {
    let before = c.hands.get("0").unwrap()
    inspect(before.post == Craft && before.order is Some(_), content="true")
    c = c.apply(Elapsed(ticks=c.next_boundary())) catch { _ => panic() }
  }
  let h = c.hands.get("0").unwrap()
  debug_inspect((h.post, h.order), content="(Drive, None)")
  inspect(c.tallies.get("0").unwrap().watches_broken, content="0")
  debug_inspect(
    try
      c.apply(Ordered(crew="1", order=Some({ phase: Coast, post: Hull, })))
    catch {
      err => err
    } noraise {
      _ => fail("expected a rejection")
    },
    content="BadOrder(phase=Coast)",
  )
  // On a hop with no coast, an order for the coast lapses at turnover.
  let short = @core.Crossing::new(plan_short(), ship())
  let short = (short.apply(Posted(crew="0", post=Hull)) catch { _ => panic() }).apply(
    Ordered(crew="0", order=Some({ phase: Coast, post: Craft, })),
  ) catch {
    _ => panic()
  }
  let landed = short.project().unwrap()
  debug_inspect(landed.hands.get("0").unwrap().post, content="Hull")
}

///|
test "a refit lands mid-crossing and stays for the next" {
  let mut c = crew([Craft, Craft, Craft])
  for i in 0..<3 {
    c = c.apply(Crafted(crew=i.to_string(), craft=Engineer)) catch {
      _ => panic()
    }
  }
  c = c.apply(Refitting(refit=Some(Injectors))) catch { _ => panic() }
  let landed = c.project().unwrap()
  inspect(landed.fit.injectors >= 1L, content="true")
  inspect(landed.fit.needed < c.fit.needed, content="true")
  let next = landed.dock().unwrap()
  inspect(next.fit == landed.fit, content="true")
}

///|
test "works delivered at port bring recruits" {
  let c = crew([Craft, Craft, Craft, Craft])
  let landed = c.project().unwrap()
  let ship = landed.dock().unwrap()
  let works = ship.records.values().fold(init=0L, (n, r) => n + r.works)
  inspect(works > 0L, content="true")
  inspect(
    ship.recruits == (works / @core.WORKS_PER_RECRUIT).min(@core.MAX_RECRUITS),
    content="true",
  )
  inspect(ship.crossings, content="1")
  inspect(c.dock() is None, content="true")
}

///|
test "law: one long gap equals two short ones" {
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], (Int32, Int32, Int32), Int64, Int64),
  ) => {
    let (steps, fit, a, b) = input
    let a = fold64(a, 100_000L) + 1L
    let b = fold64(b, 100_000L) + 1L
    let c = drive_schedule(plan20(), any_ship(fit, 333_333), steps)
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
test "law: no schedule of any events leaves the envelope" {
  let mut checked = 0
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], Bool, (Int32, Int32, Int32), Int32),
  ) => {
    let (steps, short, fit, hull) = input
    let plan = if short { plan_short() } else { plan20() }
    let c = drive_schedule(plan, any_ship(fit, hull), steps)
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
test "law: the forecast is exact" {
  let mut checked = 0
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], (Int32, Int32, Int32), Int32),
  ) => {
    let (steps, fit, hull) = input
    let c = drive_schedule(plan20(), any_ship(fit, hull), steps)
    guard c.arrived_at is None else { true }
    let at = arrival(c)
    let early = c.apply(Elapsed(ticks=at - c.t - 1L)) catch { _ => c }
    let on_time = c.apply(Elapsed(ticks=at - c.t)) catch { _ => panic() }
    checked += 1
    (at - c.t == 1L || early.arrived_at is None) &&
    on_time.arrived_at == Some(at) &&
    c.project() is Some(p) &&
    p == on_time
  })
  assert_true(checked > 0)
}

///|
/// The research's bound on events per gap: with nobody acting, a crossing
/// steps through a few dozen boundaries, never thousands. The hull band's
/// margin is what keeps a ship mending at an edge from making one a tick.
test "law: an idle crossing has few boundaries" {
  let mut most = 0
  @qc.quick_check_fn((
    input : (Array[(Int32, Int32, Int64)], (Int32, Int32, Int32), Int32),
  ) => {
    let (steps, fit, hull) = input
    let mut c = drive_schedule(plan20(), any_ship(fit, hull), steps)
    let mut n = 0
    while c.arrived_at is None && n < 10_000 {
      c = c.apply(Elapsed(ticks=c.next_boundary())) catch { _ => panic() }
      n += 1
    }
    most = most.max(n)
    n <= 256
  })
  assert_true(most > 3)
}

///|
test "a ship mending at a band edge does not chatter" {
  // Two drive hands at full burn wear faster than one hand repairs, until
  // the band drops and the lower cap lets the repair win.
  let s = {
    ..ship(hull=@core.HULL_FULL / 2L + 3_000L),
    fit: @core.Fit::new(needed=2, wear=42_000, repair=24_000),
  }
  let mut c = @core.Crossing::new(plan20(), s)
  let posts : Array[@core.Post] = [Drive, Drive, Hull]
  for i, post in posts {
    c = c.apply(Posted(crew=i.to_string(), post~)) catch { _ => panic() }
  }
  let mut n = 0
  while c.arrived_at is None {
    c = c.apply(Elapsed(ticks=c.next_boundary())) catch { _ => panic() }
    n += 1
  }
  inspect(n < 64, content="true")
}

///|
test "law: stocks stay in bounds and tallies never shrink" {
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Int32)) => {
    let (steps, hull) = input
    let mut c = @core.Crossing::new(plan20(), ship(hull=hull_of(hull)))
    let mut ok = true
    for step in steps {
      let (kind, slot, arg) = step
      let before = c
      c = c.apply(Elapsed(ticks=fold64(arg, 5400L) + 1L)) catch { _ => c }
      // Only breaking a watch takes regard away, and only from that hand.
      for crew, t in before.tallies {
        let n = c.tallies.get(crew).unwrap()
        ok = ok &&
          n.drive >= t.drive &&
          n.hull >= t.hull &&
          n.craft >= t.craft &&
          n.work >= t.work &&
          n.regard >= t.regard
      }
      c = c.apply(event_of(kind, slot, arg)) catch { _ => c }
      ok = ok &&
        0L <= c.hull &&
        c.hull <= @core.HULL_FULL &&
        c.fit.progress >= 0L &&
        c.tallies.values().all(t => t.regard >= 0L) &&
        (match c.fit.refit {
          Some(r) => c.fit.progress < c.fit.cost(r)
          None => true
        }) &&
        c.demands
        .iter()
        .zip(before.demands.iter())
        .all(p => p.0.status >= p.1.status)
    }
    ok
  })
}

///|
test "law: a crossing survives a JSON round trip" {
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Int32)) => {
    let (steps, hull) = input
    let c = drive_schedule(plan20(), ship(hull=hull_of(hull)), steps)
    let back : @core.Crossing = @json.from_json(c.to_json()) catch {
      _ => panic()
    }
    back == c && back.forecast() == c.forecast()
  })
}

///|
test "law: refits only ever help" {
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Int32)) => {
    let (steps, hull) = input
    let c = drive_schedule(plan20(), ship(hull=hull_of(hull)), steps)
    let s = ship()
    c.fit.needed <= s.fit.needed &&
    c.fit.needed >= 2L &&
    c.fit.wear <= s.fit.wear &&
    c.fit.repair >= s.fit.repair &&
    c.fit.baffles <= @core.MAX_LEVEL &&
    c.fit.plating <= @core.MAX_LEVEL &&
    c.fit.injectors <= @core.MAX_LEVEL &&
    c.fit.coils <= @core.MAX_LEVEL
  })
}

///|
test "law: docking delivers every work unit exactly once" {
  let mut checked = 0
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Int64)) => {
    let (steps, seed) = input
    let c = drive_schedule(plan20(), ship(seed~), steps)
    guard c.project() is Some(landed) else { false }
    guard landed.dock() is Some(next) else { false }
    checked += 1
    landed.tallies
    .iter()
    .all(p => {
      let (crew, t) = p
      let r = next.records.get(crew).unwrap()
      r.works * @core.WORK_SIZE + r.carry == t.work &&
      r.regard == t.regard &&
      r.carry < @core.WORK_SIZE
    }) &&
    next.hull >= landed.hull &&
    next.recruits <= @core.MAX_RECRUITS
  })
  assert_true(checked > 0)
}

///|
test "law: another hand on the drive never delays arrival" {
  let mut checked = 0
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Int32)) => {
    let (steps, slot) = input
    let c = drive_schedule(plan20(), ship(), steps)
    guard c.phase != Arrived else { true }
    let slot = 100 + fold(slot, 8)
    let more = c.apply(Posted(crew=slot.to_string(), post=Drive)) catch {
      _ => panic()
    }
    // A hand taken from the hull may cost a band later; compare like with
    // like by adding a new hand rather than moving one.
    checked += 1
    arrival(more) <= arrival(c)
  })
  assert_true(checked > 0)
}

///|
test "exhaustive: the setting is monotone in drive quarters and within bounds" {
  let mut checked = 0
  for needed in 1L..<=64L {
    for cap in [350L, 512L, 675L, 837L, 1000L] {
      let mut last = @math.SETTING_FLOOR
      for drive in 0L..<=80L {
        let s = @math.setting(drive, needed, cap)
        assert_true(s >= last && s >= @math.SETTING_FLOOR && s <= cap)
        last = s
        checked += 1
      }
    }
  }
  inspect(checked, content="25920")
}

///|
test "the schedules the laws use reach every mechanic" {
  let seen = Array::make(6, 0)
  @qc.quick_check_fn(
    (steps : Array[(Int32, Int32, Int64)]) => {
      let c = drive_schedule(plan20(), ship(), steps)
      guard c.project() is Some(p) else { false }
      let hits = [
        c.hands.values().any(h => h.order is Some(_)) &&
        p.hands.values().all(h => h.order is None),
        p.tallies.values().any(t => t.watches_stood > 0L),
        p.tallies.values().any(t => t.watches_broken > 0L),
        p.demands.iter().any(d => d.status == Met),
        p.demands.iter().any(d => d.status == Missed),
        p.fit.baffles + p.fit.plating + p.fit.injectors + p.fit.coils > 0L,
      ]
      for i, hit in hits {
        if hit {
          seen[i] += 1
        }
      }
      true
    },
    max_success=500,
  )
  assert_true(seen.all(n => n > 0), msg=seen.map(n => n.to_string()).join(", "))
}
