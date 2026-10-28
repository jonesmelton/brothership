///|
fn page_profile() -> @ships.Profile {
  @ships.fleet()[0].profile
}

///|
fn fold32(x : Int32, m : Int32) -> Int32 {
  (x % m + m) % m
}

///|
/// The first fleet ship in port, just after its first tick.
fn in_port(seed~ : Int64 = 1L) -> @core.State {
  let p = page_profile()
  let (_, s) = p.due(
    @core.State::initial(p.ship(seed~), profile=p.name),
    1_800_000_000L,
  )
  s
}

///|
/// Underway, crew "0".."n" take `posts`, then `ticks` pass.
fn sea(
  posts~ : Array[@core.Post] = [],
  ticks~ : Int64 = 0L,
  seed~ : Int64 = 1L,
) -> @core.State {
  let p = page_profile()
  let (_, s) = p.due(
    @core.State::initial(p.ship(seed~), profile=p.name),
    1_800_000_000L,
  )
  let (_, s) = p.due(s, 1_800_000_600L)
  let mut s = s
  for i, post in posts {
    s = s.apply(@core.Crew(crew=i.to_string(), intent=@core.Posted(post~))) catch {
      _ => s
    }
  }
  s.apply(@core.Tick(at=s.at + ticks)) catch {
    _ => s
  }
}

///|
/// The same ship, advanced to `phase`.
fn until_phase(s : @core.State, phase : @core.Phase) -> @core.State {
  let mut s = s
  for _ in 0..<4096 {
    guard s.crossing() is Some(c) else { break }
    if c.phase >= phase {
      break
    }
    s = s.apply(@core.Tick(at=s.at + c.next_boundary())) catch { _ => break }
  }
  s
}

///|
/// Flown until the first docking, in port.
fn docked(posts~ : Array[@core.Post] = [], seed~ : Int64 = 1L) -> @core.State {
  let p = page_profile()
  let mut s = sea(posts~, seed~)
  for _ in 0..<1000 {
    if s.ship.crossings > 0L {
      break
    }
    s = p.due(s, s.at + 600L).1
  }
  s
}

///|
test "the pages are named as their headings say" {
  debug_inspect(
    [You, Voyage, Ship].map(Page::name),
    content=(
      #|["You", "Voyage", "Ship"]
    ),
  )
}

///|
test "each happening has one page" {
  let story : Array[@core.Entry] = [
    { seq: 1, at: 0, happening: Departed, },
    { seq: 2, at: 0, happening: Took(crew="0", post=Drive), },
    { seq: 3, at: 0, happening: Took(crew="1", post=Hull), },
    { seq: 4, at: 0, happening: Stood(crew="0"), },
    { seq: 5, at: 0, happening: Finished(crew="1"), },
    { seq: 6, at: 0, happening: Landed(refit=Baffles, level=1), },
    { seq: 7, at: 0, happening: Asked(post=None), },
    { seq: 8, at: 0, happening: Docked(recruits=1), },
    { seq: 9, at: 0, happening: Spoke(line="Well rowed.", about=4), },
    { seq: 10, at: 0, happening: Spoke(line="Who goes there?", about=99), },
  ]
  debug_inspect(
    story.map(e => page_of(e, you="0", story~)),
    content=(
      #|[Voyage, You, Ship, You, Ship, Ship, Ship, Voyage, You, Ship]
    ),
  )
}

///|
test "effect of nothing" {
  let s = sea(posts=[Drive, Hull])
  debug_inspect(
    effect(s, s, you="0"),
    content=(
      #|["No change to arrival."]
    ),
  )
  debug_inspect(
    effect(in_port(), in_port(), you="0"),
    content=(
      #|[]
    ),
  )
}

///|
/// `s` with `crew` proposing `intent`, at the same instant.
fn propose(
  s : @core.State,
  crew : String,
  intent : @core.Intent,
) -> @core.State {
  s.apply(@core.Crew(crew~, intent~)) catch {
    _ => panic()
  }
}

///|
test "effect: a hand on the drive" {
  let before = sea()
  let after = propose(before, "0", Posted(post=Drive))
  debug_inspect(
    effect(before, after, you="0"),
    content=(
      #|[
      #|  "Arrival about 6 hours sooner.",
      #|  "You now earn 2 hours of regard an hour.",
      #|]
    ),
  )
}

///|
test "effect: a hand on the hull while it wears" {
  let before = sea(posts=[Drive, Drive, Drive], ticks=3600L)
  guard before.crossing() is Some(c) else { panic() }
  inspect(c.trend("").hull < 0L, content="true")
  let after = propose(before, "3", Posted(post=Hull))
  debug_inspect(
    effect(before, after, you="3"),
    content=(
      #|["Arrival about 40 minutes sooner.", "The hull now mends."]
    ),
  )
}

///|
test "effect: a drive hand in the coast still shortens the approach" {
  let before = until_phase(sea(posts=[Hull, Craft]), Coast)
  guard before.crossing() is Some(c) else { panic() }
  inspect(c.phase is Coast, content="true")
  let after = propose(before, "2", Posted(post=Drive))
  debug_inspect(
    effect(before, after, you="2"),
    content=(
      #|["Arrival about 3 hours sooner."]
    ),
  )
}

///|
test "effect: a hand that saves a demand" {
  // The first crew and seed where one more hand on a demand's post turns
  // its outcome from missed to met.
  let found = for seed in 1L..<40L {
    let before = sea(posts=[Drive], ticks=1800L, seed~)
    guard before.crossing() is Some(c) && c.outcomes() is Some(out) else {
      continue
    }
    let flipped = for i, d in c.demands {
      guard out[i].status == Missed && d.status is (Waiting | Open) else {
        continue
      }
      let after = propose(before, "1", Posted(post=d.hazard.post()))
      guard after.crossing() is Some(a) && a.outcomes() is Some(now) else {
        continue
      }
      if now[i].status == Met {
        break Some(effect(before, after, you="1"))
      }
    } nobreak {
      None
    }
    if flipped is Some(lines) {
      break Some(lines)
    }
  } nobreak {
    None
  }
  debug_inspect(
    found,
    content=(
      #|Some(["Breach will now be met.", "The hull now mends."])
    ),
  )
}

///|
test "ledger totals do not fall across a docking" {
  let start = sea(posts=[Drive, Hull])
  let early = Ledger::of(start, you="0")
  let docked = docked(posts=[Drive, Hull])
  debug_inspect(
    early,
    content=(
      #|{ at: 1800000600, regard: 0, works: 0, crossings: 1 }
    ),
  )
  debug_inspect(
    Ledger::of(docked, you="0"),
    content=(
      #|{ at: 1800045000, regard: 270620, works: 0, crossings: 1 }
    ),
  )
  debug_inspect(
    since(early, Ledger::of(docked, you="0")),
    content=(
      #|["You earned 18 hours of regard."]
    ),
  )
  debug_inspect(
    Ledger::of(in_port(), you="0"),
    content=(
      #|{ at: 1800000000, regard: 0, works: 0, crossings: 0 }
    ),
  )
}

///|
test "since names what was earned" {
  let before : Ledger = {
    at: 0,
    regard: 36L * @core.REGARD_HOUR,
    works: 0,
    crossings: 0,
  }
  let now : Ledger = {
    at: 600,
    regard: 42L * @core.REGARD_HOUR,
    works: 2,
    crossings: 1,
  }
  debug_inspect(
    since(before, now),
    content=(
      #|[
      #|  "You earned 6 hours of regard.",
      #|  "You finished 2 works.",
      #|  "You reached rank 1.",
      #|]

    ),
  )
  debug_inspect(
    since(now, now),
    content=(
      #|[]
    ),
  )
}

///|
test "what a driver earns" {
  let s = sea(posts=[Drive, Hull, Hull])
  debug_inspect(
    earning_sentences(s, you="0"),
    content=(
      #|[
      #|  "No regard yet this crossing, earning 2 an hour.",
      #|  "Doubled: the ship asks for the drive.",
      #|  "40 hours of regard to rank 1.",
      #|]
    ),
  )
  debug_inspect(
    earning_sentences(sea(), you="0"),
    content=(
      #|[]
    ),
  )
}

///|
test "what an artist earns" {
  let s = sea(posts=[Craft], ticks=2L * 3600L)
  debug_inspect(
    earning_sentences(s, you="0"),
    content=(
      #|[
      #|  "4 hours of regard this crossing, earning 2 an hour.",
      #|  "Work 1: 2 of 6 crew-hours.",
      #|  "36 hours of regard to rank 1.",
      #|]
    ),
  )
  debug_inspect(
    earning_sentences(sea(posts=[Craft]), you="0"),
    content=(
      #|[
      #|  "No regard yet this crossing, earning 2 an hour.",
      #|  "Work 1: 0 of 6 crew-hours.",
      #|  "40 hours of regard to rank 1.",
      #|]
    ),
  )
}

///|
test "how the demands will close" {
  let s = sea(posts=[Drive, Hull, Hull])
  guard s.crossing() is Some(c) else { panic() }
  debug_inspect(
    outlook_sentences(c),
    content=(
      #|[
      #|  "Flare will be missed by about a crew-hour.",
      #|  "Breach will be met with about an hour to spare.",
      #|]
    ),
  )
  guard s.crossing() is Some(_) else { panic() }
  let waiting = sea(posts=[Drive])
  guard waiting.crossing() is Some(w) else { panic() }
  debug_inspect(
    outlook_sentences(w),
    content=(
      #|[
      #|  "Flare will be missed by about a crew-hour.",
      #|  "Breach will be missed by about 2 crew-hours.",
      #|]
    ),
  )
}

///|
test "the ship page in port and under way" {
  debug_inspect(
    ship_sentences(in_port()),
    content=(
      #|[
      #|  "Hull at 100%.",
      #|  "Recruits: 0 of 6.",
      #|  "0 of 3 works toward the next recruit.",
      #|]
    ),
  )
  debug_inspect(
    ship_sentences(sea(posts=[Drive], ticks=3600L)),
    content=(
      #|[
      #|  "Hull at 97%, wearing about 2.9% an hour.",
      #|  "Plating to level 1: 0% built, with no engineer at work.",
      #|  "Recruits: 0 of 6.",
      #|  "0 of 3 works toward the next recruit.",
      #|]

    ),
  )
  debug_inspect(
    ship_sentences(sea(posts=[Hull, Hull], ticks=3600L)),
    content=(
      #|[
      #|  "Hull at 100%.",
      #|  "Plating to level 1: 0% built, with no engineer at work.",
      #|  "Recruits: 0 of 6.",
      #|  "0 of 3 works toward the next recruit.",
      #|]

    ),
  )
}

///|
test "the ship page with a refit under way" {
  let mut s = sea(posts=[Craft, Craft])
  s = s.apply(@core.Crew(crew="0", intent=@core.Crafted(craft=@core.Engineer))) catch {
    _ => s
  }
  s = s.apply(@core.Crew(crew="1", intent=@core.Crafted(craft=@core.Engineer))) catch {
    _ => s
  }
  s = s.apply(@core.Refitting(refit=Some(@core.Baffles))) catch { _ => s }
  s = s.apply(@core.Tick(at=s.at + 3600L)) catch { _ => s }
  debug_inspect(
    ship_sentences(s),
    content=(
      #|[
      #|  "Hull at 99%, wearing about 1% an hour.",
      #|  "Baffles to level 1: 50% built, about an hour to go at this rate.",
      #|  "Recruits: 0 of 6.",
      #|  "0 of 3 works toward the next recruit.",
      #|]

    ),
  )
}

///|
test "what each refit level does" {
  let lines : Array[String] = []
  for refit in @core.refits {
    for level in 0L..<=@core.MAX_LEVEL {
      lines.push(
        "\{refit_label(refit)} \{level}: \{refit_effect(refit, level)}",
      )
    }
  }
  debug_inspect(
    lines,
    content=(
      #|[
      #|  "Baffles 0: not fitted",
      #|  "Baffles 1: hull wears 25% less",
      #|  "Baffles 2: hull wears 44% less",
      #|  "Baffles 3: hull wears 58% less",
      #|  "Plating 0: not fitted",
      #|  "Plating 1: hull hands mend 25% more",
      #|  "Plating 2: hull hands mend 56% more",
      #|  "Plating 3: hull hands mend 95% more",
      #|  "Injectors 0: not fitted",
      #|  "Injectors 1: 1 fewer drive hand for full burn",
      #|  "Injectors 2: 2 fewer drive hands for full burn",
      #|  "Injectors 3: 3 fewer drive hands for full burn",
      #|  "Coils 0: not fitted",
      #|  "Coils 1: the γ cap a fifth higher, from the next departure",
      #|  "Coils 2: the γ cap 44% higher, from the next departure",
      #|  "Coils 3: the γ cap 73% higher, from the next departure",
      #|]
    ),
  )
}

///|
test "a landed refit names its effect" {
  debug_inspect(
    [
      told(Landed(refit=Baffles, level=2), you="0", ship="The Tigress"),
      told(Landed(refit=Plating, level=1), you="0", ship="The Tigress"),
      told(Landed(refit=Injectors, level=1), you="0", ship="The Tigress"),
      told(Landed(refit=Coils, level=3), you="0", ship="The Tigress"),
    ],
    content=(
      #|[
      #|  "A refit landed: baffles to level 2, hull wears 44% less.",
      #|  "A refit landed: plating to level 1, hull hands mend 25% more.",
      #|  "A refit landed: injectors to level 1, 1 fewer drive hand for full burn.",
      #|  "A refit landed: coils to level 3, the γ cap 73% higher, from the next departure.",
      #|]
    ),
  )
}

///|
/// No sentence spoken to a player is empty or carries markdown or emoji.
fn is_clean(line : String) -> Bool {
  !line.is_empty() &&
  !line.contains("*") &&
  !line.contains("#") &&
  !line.contains("_") &&
  !line.contains("`") &&
  line.to_array().all(ch => ch.to_int() < 0x2500)
}

///|
/// The first six posts a generator names, as posts.
fn posts_of(posts : Array[Int32]) -> Array[@core.Post] {
  let ps : Array[@core.Post] = [Drive, Hull, Craft]
  let out : Array[@core.Post] = []
  for i in 0..<posts.length().min(6) {
    out.push(ps[fold32(posts[i], 3)])
  }
  out
}

///|
test "law: effect of a state on itself claims no change" {
  let mut checked = 0
  @qc.quick_check_fn((input : (Array[Int32], Int32)) => {
    let (posts, ticks) = input
    let s = sea(posts=posts_of(posts), ticks=fold32(ticks, 20_000).to_int64())
    let lines = effect(s, s, you="0")
    checked += 1
    lines.length() <= 1 &&
    lines.all(l => {
      !l.contains("sooner") && !l.contains("later") && !l.contains(" now ")
    })
  })
  assert_true(checked > 0)
}

///|
test "law: effect is at most two sentences" {
  let mut checked = 0
  @qc.quick_check_fn((input : (Array[Int32], Int32, Int32)) => {
    let (posts, kind, arg) = input
    let ps : Array[@core.Post] = [Drive, Hull, Craft]
    let before = sea(
      posts=posts_of(posts),
      ticks=fold32(arg, 10_000).to_int64(),
    )
    let intent = match fold32(kind, 3) {
      0 => @core.Intent::Posted(post=ps[fold32(arg, 3)])
      1 =>
        @core.Intent::Watched(
          ticks=fold32(arg, 12).to_int64() * @core.HOUR + @core.HOUR,
        )
      _ =>
        @core.Intent::Crafted(
          craft=if arg % 2 == 0 { Engineer } else { Artist },
        )
    }
    let after = before.apply(@core.Crew(crew="7", intent~)) catch {
      _ => before
    }
    let lines = effect(before, after, you="7")
    checked += 1
    lines.length() <= 2 && lines.all(is_clean)
  })
  assert_true(checked > 0)
}

///|
test "law: a ledger never falls" {
  let mut checked = 0
  let mut sailed = 0
  @qc.quick_check_fn((steps : Array[(Int32, Int32, Int32)]) => {
    let p = page_profile()
    let ps : Array[@core.Post] = [Drive, Hull, Craft]
    let mut s = sea()
    let mut last = Ledger::of(s, you="0")
    let mut ok = true
    for i in 0..<steps.length().min(30) {
      let (slot, post, wait) = steps[i]
      s = p.due(s, s.at + fold32(wait, 2400).to_int64() + 60L).1
      s = s.apply(
        @core.Crew(
          crew=fold32(slot, 6).to_string(),
          intent=@core.Intent::Posted(post=ps[fold32(post, 3)]),
        ),
      ) catch {
        _ => s
      }
      let now = Ledger::of(s, you="0")
      ok = ok &&
        now.at >= last.at &&
        now.regard >= last.regard &&
        now.works >= last.works &&
        now.crossings >= last.crossings
      last = now
    }
    if s.ship.crossings > 0L {
      sailed += 1
    }
    checked += 1
    ok
  })
  assert_true(checked > 0)
  assert_true(sailed > 0)
}

///|
test "law: nothing earned between one ledger and itself" {
  let mut checked = 0
  @qc.quick_check_fn((input : (Array[Int32], Int32)) => {
    let (posts, ticks) = input
    let s = sea(posts=posts_of(posts), ticks=fold32(ticks, 30_000).to_int64())
    let l = Ledger::of(s, you="0")
    checked += 1
    since(l, l).is_empty()
  })
  assert_true(checked > 0)
}

///|
test "law: a spoken line follows the page of what it is about" {
  let mut checked = 0
  @qc.quick_check_fn((input : (Array[Int32], Array[Int32])) => {
    let (kinds, abouts) = input
    let story : Array[@core.Entry] = []
    let ys : Array[String] = ["0", "1"]
    for i in 0..<kinds.length().min(12) {
      let k = kinds[i]
      let happening : @core.Happening = match fold32(k, 13) {
        0 => Departed
        1 => Began(phase=Coast)
        2 => Began(phase=Arrived)
        3 => Docked(recruits=fold32(k, 4).to_int64())
        4 => Opened(hazard=Breach)
        5 => Met(hazard=Flare)
        6 => Missed(hazard=Salvage)
        7 => Landed(refit=Baffles, level=1)
        8 => Asked(post=None)
        9 => Took(crew=ys[fold32(k, 2)], post=Hull)
        10 => Left(crew=ys[fold32(k, 2)])
        11 => Stood(crew=ys[fold32(k, 2)])
        _ => Finished(crew=ys[fold32(k, 2)])
      }
      story.push({ seq: (i + 1).to_int64(), at: 0, happening, })
    }
    let plain = story.copy()
    for i in 0..<abouts.length().min(8) {
      let a = abouts[i]
      story.push({
        seq: (100 + i).to_int64(),
        at: 0,
        happening: Spoke(
          line="A line.",
          about=if a % 5 == 0 || plain.is_empty() {
            999L
          } else {
            plain[fold32(a, plain.length())].seq
          },
        ),
      })
    }
    let mut ok = true
    for e in story {
      match e.happening {
        Spoke(about~, ..) => {
          let expected = match story.iter().find_first(x => x.seq == about) {
            Some(x) => page_of(x, you="0", story~)
            None => Ship
          }
          ok = ok && page_of(e, you="0", story~) == expected
        }
        Took(crew~, ..) | Left(crew~) | Stood(crew~) | Finished(crew~) =>
          ok = ok &&
            page_of(e, you="0", story~) ==
            (if crew == "0" { You } else { Ship })
        _ =>
          ok = ok &&
            page_of(e, you="0", story~) ==
            (if e.happening
              is (Departed
              | Began(_)
              | Docked(_)
              | Opened(_)
              | Met(_)
              | Missed(_)) {
              Voyage
            } else {
              Ship
            })
      }
    }
    checked += 1
    ok
  })
  assert_true(checked > 0)
}

///|
test "law: every page sentence is plain text" {
  let mut checked = 0
  @qc.quick_check_fn((input : (Array[Int32], Int32)) => {
    let (posts, ticks) = input
    let s = sea(posts=posts_of(posts), ticks=fold32(ticks, 30_000).to_int64())
    let lines : Array[String] = []
    lines.push(Page::name(You))
    lines.push(Page::name(Voyage))
    lines.push(Page::name(Ship))
    for line in ship_sentences(s) {
      lines.push(line)
    }
    for line in earning_sentences(s, you="0") {
      lines.push(line)
    }
    for line in since(Ledger::of(s, you="0"), Ledger::of(s, you="0")) {
      lines.push(line)
    }
    if s.crossing() is Some(c) {
      for line in outlook_sentences(c) {
        lines.push(line)
      }
    }
    for refit in @core.refits {
      for level in 0L..<=@core.MAX_LEVEL {
        lines.push(refit_effect(refit, level))
      }
      lines.push(told(Landed(refit~, level=2), you="0", ship="The Tigress"))
    }
    checked += 1
    lines.all(is_clean)
  })
  assert_true(checked > 0)
}
