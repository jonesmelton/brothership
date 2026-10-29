///|
/// A crossing with `craft` crafters: hand "0" the artist or engineer given.
fn crafters(k : @core.Craft, n : Int32) -> @core.Crossing {
  let mut c = crew(Array::make(n, @core.Post::Craft))
  for i in 0..<n {
    c = c.apply(Crafted(crew=i.to_string(), craft=k)) catch { _ => panic() }
  }
  c
}

///|
fn hand(c : @core.Crossing, crew : String) -> @core.Hand {
  c.hands.get(crew).unwrap()
}

///|
fn after(c : @core.Crossing, ticks : Int64) -> @core.Crossing {
  c.apply(Elapsed(ticks~)) catch {
    _ => panic()
  }
}

///|
test "flow banks craft work instead of making it" {
  let c = after(crafters(Artist, 1), @core.HOUR)
  inspect(hand(c, "0").banked, content="57600")
  inspect(c.tallies.get("0").unwrap().work, content="0")
  let e = after(crafters(Engineer, 1), @core.HOUR)
  inspect(hand(e, "0").banked, content="57600")
  inspect(e.fit.progress, content="0")
}

///|
test "a hand on a ship post banks nothing" {
  let c = after(crew([Drive, Hull]), @core.HOUR)
  inspect(c.hands.values().all(h => h.banked == 0L), content="true")
}

///|
test "making applies the percent to an artist's work" {
  let c = after(crafters(Artist, 1), 2L * @core.HOUR)
  let percent = @core.craft_percent(1L, "0", c.t)
  let made = c.apply(Made(crew="0")) catch { _ => panic() }
  inspect(hand(made, "0").banked, content="0")
  inspect(
    made.tallies.get("0").unwrap().work == 115200L * percent / 100L,
    content="true",
  )
  inspect(percent >= 100L && percent <= 150L, content="true")
}

///|
test "making finishes a work" {
  let mut c = after(crafters(Artist, 1), 6L * @core.HOUR)
  c = c.apply(Made(crew="0")) catch { _ => panic() }
  inspect(c.tallies.get("0").unwrap().work >= @core.WORK_SIZE, content="true")
}

///|
test "making lands a refit" {
  let mut c = crafters(Engineer, 3)
  c = c.apply(Refitting(refit=Some(Injectors))) catch { _ => panic() }
  c = after(c, 2L * @core.HOUR)
  inspect(c.fit.injectors, content="0")
  inspect(c.fit.progress, content="0")
  for i in 0..<3 {
    c = c.apply(Made(crew=i.to_string())) catch { _ => panic() }
  }
  inspect(c.fit.injectors, content="1")
}

///|
test "a refit does not land on its own" {
  let mut c = crafters(Engineer, 3)
  c = c.apply(Refitting(refit=Some(Injectors))) catch { _ => panic() }
  let landed = c.project().unwrap()
  inspect(landed.fit.injectors, content="0")
  inspect(landed.fit.progress, content="0")
}

///|
test "nothing banked is refused" {
  let c = crafters(Artist, 1)
  let reject = (event : @core.CrossingEvent) => {
    try c.apply(event) catch {
      err => err
    } noraise {
      _ => fail("expected a rejection")
    }
  }
  debug_inspect(reject(Made(crew="0")), content="NothingBanked(crew=\"0\")")
  debug_inspect(reject(Made(crew="ghost")), content="NotAboard(crew=\"ghost\")")
}

///|
test "making works at any post and when arrived" {
  let mut c = crafters(Artist, 1)
  c = after(c, @core.HOUR)
  c = c.apply(Posted(crew="0", post=Drive)) catch { _ => panic() }
  inspect(hand(c, "0").banked, content="57600")
  c = c.apply(Crafted(crew="0", craft=Engineer)) catch { _ => panic() }
  inspect(hand(c, "0").banked, content="57600")
  c = c.apply(Made(crew="0")) catch { _ => panic() }
  inspect(c.fit.progress >= 57600L, content="true")
  let mut d = crafters(Artist, 1)
  d = d.project().unwrap()
  inspect(d.phase == Arrived, content="true")
  inspect(hand(d, "0").banked > 0L, content="true")
  d = d.apply(Made(crew="0")) catch { _ => panic() }
  inspect(hand(d, "0").banked, content="0")
}

///|
test "leaving makes banked work at 100 percent" {
  let mut c = after(crafters(Artist, 1), @core.HOUR)
  c = c.apply(Left(crew="0")) catch { _ => panic() }
  inspect(c.tallies.get("0").unwrap().work, content="57600")
  let mut e = after(crafters(Engineer, 1), @core.HOUR)
  e = e.apply(Left(crew="0")) catch { _ => panic() }
  inspect(e.fit.progress, content="57600")
}

///|
test "docking makes banked work at 100 percent" {
  let landed = crafters(Artist, 2).project().unwrap()
  let banked = hand(landed, "0").banked
  let next = landed.dock().unwrap()
  let r = next.records.get("0").unwrap()
  inspect(r.works * @core.WORK_SIZE + r.carry, content=banked.to_string())
}

///|
test "docking an engineer's bank lands the refit in the fit" {
  let mut c = crafters(Engineer, 3)
  c = c.apply(Refitting(refit=Some(Injectors))) catch { _ => panic() }
  let landed = c.project().unwrap()
  inspect(landed.fit.injectors, content="0")
  let next = landed.dock().unwrap()
  inspect(next.fit.injectors > 0L, content="true")
}

///|
test "the percent is pinned on every target" {
  inspect(
    @core.craft_percent(1L, "0", 0L),
    content=(
      #|123
    ),
  )
  inspect(
    @core.craft_percent(1L, "0", 3600L),
    content=(
      #|111
    ),
  )
  inspect(
    @core.craft_percent(7L, "ann", 12345L),
    content=(
      #|128
    ),
  )
  inspect(
    @core.craft_percent(-9L, "bo\u{4e2d}", 999999L),
    content=(
      #|105
    ),
  )
}

///|
test "law: the percent is in range and a function of its inputs" {
  @qc.quick_check_fn((input : (Int64, String, Int64)) => {
    let (seed, crew, t) = input
    let p = @core.craft_percent(seed, crew, t)
    p >= 100L && p <= 150L && p == @core.craft_percent(seed, crew, t)
  })
}

///|
test "the percent varies" {
  let seen : Map[Int64, Bool] = Map([])
  for t in 0L..<200L {
    seen[@core.craft_percent(1L, "ann", t)] = true
  }
  inspect(seen.length() > 20, content="true")
}

///|
test "law: banked work is never lost" {
  @qc.quick_check_fn((input : (Array[(Int32, Int32, Int64)], Int64)) => {
    let (steps, seed) = input
    let c = drive_schedule(plan20(), ship(seed~), steps)
    guard c.project() is Some(landed) else { false }
    guard landed.dock() is Some(next) else { false }
    let banked = landed.hands.values().fold(init=0L, (n, h) => n + h.banked)
    let artists = landed.hands
      .iter()
      .fold(init=0L, (n, p) => {
        let (_, h) = p
        if h.craft == Artist {
          n + h.banked
        } else {
          n
        }
      })
    let units = landed.tallies.values().fold(init=0L, (n, t) => n + t.work)
    let kept = next.records
      .values()
      .fold(init=0L, (n, r) => n + r.works * @core.WORK_SIZE + r.carry)
    banked >= artists && kept == units + artists
  })
}
