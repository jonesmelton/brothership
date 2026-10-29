///|
/// The story of the ship's first crossing, from departure to docking, with
/// crew "0".."n" on `posts`, as the server would have derived it.
fn first_landfall(
  posts~ : Array[@core.Post] = [],
  records~ : Map[String, @core.Record] = {},
) -> (Array[@core.Entry], Int64) {
  let p = page_profile()
  let mut s = sea(posts~, records~)
  let entries : Array[@core.Entry] = []
  let mut seq = 0L
  let log = (before : @core.State, events : Array[@core.Event]) => {
    let mut s = before
    for e in events {
      let next = s.apply(e) catch { _ => panic() }
      for h in @core.happenings(s, e, next) {
        seq += 1L
        entries.push({ seq, at: next.at, happening: h, })
      }
      s = next
    }
  }
  entries.push({ seq: 0L, at: s.at, happening: Departed, })
  for _ in 0..<1000 {
    if s.ship.crossings > 0L {
      break
    }
    let (events, next) = p.due(s, s.at + 600L, officer=_ => true)
    log(s, events)
    s = next
  }
  (entries, s.at)
}

///|
test "no landfall before a crossing ends" {
  debug_inspect(
    landfall_sentences([], you="0", now=0L),
    content=(
      #|["No landfall yet. The ship has not finished a crossing."]
    ),
  )
  debug_inspect(landfall_away([], after=0L, upto=9L), content="[]")
}

///|
test "landfall of a crossing flown by the script" {
  let (story, now) = first_landfall(posts=[Drive, Hull, Craft])
  debug_inspect(
    landfall_sentences(story, you="0", now=now + 7200L),
    content=(
      #|[
      #|  "Made Occitan from Kerala: 14 hours aboard, 15.7 years at the worlds.",
      #|  "Landfall was about 2 hours ago.",
      #|  "Promoted at the muster: you to lieutenant junior grade.",
      #|  "Nobody answered the ship's 4 asks.",
      #|  "The crossing delivered 2 works and gained no recruits.",
      #|]
    ),
  )
}

///|
test "landfall with a promotion at the muster" {
  let veteran : @core.Record = {
    regard: 600 * @core.REGARD_HOUR,
    works: 0,
    carry: 0,
    rank: Some(0L),
    served: 100 * @core.HOUR,
  }
  let (story, now) = first_landfall(posts=[Drive, Hull, Craft], records={
    "0": veteran,
    "1": veteran,
  })
  debug_inspect(
    landfall_sentences(story, you="0", now~),
    content=(
      #|[
      #|  "Made Occitan from Kerala: 14 hours aboard, 15.7 years at the worlds.",
      #|  "Landfall was just now.",
      #|  "Promoted at the muster: you to lieutenant junior grade.",
      #|  "Nobody answered the ship's 4 asks.",
      #|  "The crossing delivered 2 works and gained no recruits.",
      #|]
    ),
  )
}

///|
test "while you were away points to a landfall the player missed" {
  let (story, _) = first_landfall(posts=[Drive])
  let docked = story.last().unwrap().seq
  debug_inspect(
    landfall_away(story, after=docked - 3L, upto=docked),
    content=(
      #|["Landfall at Occitan. The account is under Landfall on this page."]
    ),
  )
  debug_inspect(
    landfall_away(story, after=docked, upto=docked + 5L),
    content="[]",
  )
}

///|
test "arrival is one short batch: only your own promotion is announced" {
  let story : Array[@core.Entry] = []
  let you = priority(
    {
      seq: 1,
      at: 0,
      happening: Promoted(crew="0", rank=2, tally=zero_tally()),
    },
    you="0",
    story~,
  )
  let other = priority(
    {
      seq: 2,
      at: 0,
      happening: Promoted(crew="1", rank=2, tally=zero_tally()),
    },
    you="0",
    story~,
  )
  debug_inspect((you, other), content="(Announce, Quiet)")
}

///|
test "landfall with nobody aboard says so" {
  let (story, now) = first_landfall()
  debug_inspect(
    landfall_sentences(story, you="0", now~),
    content=(
      #|[
      #|  "Made Occitan from Kerala: 19 hours aboard, 15.7 years at the worlds.",
      #|  "Landfall was just now.",
      #|  "Nobody was promoted at the muster.",
      #|  "Nobody answered the ship's 4 asks.",
      #|  "The crossing delivered no works and gained no recruits.",
      #|]
    ),
  )
}

///|
test "landfall counts who answered the ship's asks, in order of the roll call" {
  let (flown, now) = first_landfall(posts=[Drive])
  guard flown.last() is Some({ happening: Docked(landing~, ..), .. }) else {
    panic()
  }
  let story : Array[@core.Entry] = [
    { seq: 1, at: 0, happening: Departed, },
    { seq: 2, at: 0, happening: Asked(post=Some(Drive)), },
    { seq: 3, at: 0, happening: Took(crew="0", post=Drive), },
    { seq: 4, at: 0, happening: Took(crew="1", post=Drive), },
    { seq: 5, at: 0, happening: Asked(post=Some(Hull)), },
    { seq: 6, at: 0, happening: Took(crew="1", post=Hull), },
    { seq: 7, at: 0, happening: Began(phase=Arrived), },
    {
      seq: 8,
      at: 0,
      happening: Promoted(crew="1", rank=1, tally=zero_tally()),
    },
    {
      seq: 9,
      at: 0,
      happening: Promoted(crew="0", rank=2, tally=zero_tally()),
    },
    { seq: 10, at: now, happening: Docked(recruits=1, landing~), },
  ]
  debug_inspect(
    landfall_sentences(story, you="0", now~),
    content=(
      #|[
      #|  "Made Occitan from Kerala: 14 hours aboard, 15.7 years at the worlds.",
      #|  "Landfall was just now.",
      #|  "Promoted at the muster: a hand to lieutenant junior grade, you to lieutenant.",
      #|  "The ship's 2 asks were answered 3 times, 1 of them by you.",
      #|  "The crossing delivered no works and gained 1 recruit.",
      #|]
    ),
  )
}
