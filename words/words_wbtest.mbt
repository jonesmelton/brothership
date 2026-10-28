///|
test "arrival words coarsen with distance" {
  let h = 3600L
  let at : Array[Int64] = [
    0,
    59 * 60,
    h,
    89 * 60,
    90 * 60,
    5 * h,
    6 * h,
    13 * h,
    35 * h,
    36 * h,
    80 * h,
  ]
  debug_inspect(
    at.map(in_words),
    content=(
      #|[
      #|  "within the hour",
      #|  "within the hour",
      #|  "in about an hour",
      #|  "in about an hour",
      #|  "in about 2 hours",
      #|  "in about 5 hours",
      #|  "in about 6 hours",
      #|  "in about 12 hours",
      #|  "in about 36 hours",
      #|  "in about 2 days",
      #|  "in about 3 days",
      #|]
    ),
  )
}

///|
test "an empty ship says so instead of counting zeroes" {
  let p = @ships.fleet()[0].profile
  let (_, s) = p.due(
    @core.State::initial(p.ship(seed=1), profile=p.name),
    1_800_000_000,
  )
  let (_, sea) = p.due(s, 1_800_000_600)
  debug_inspect(
    where_sentences(sea),
    content=(
      #|[
      #|  "Burning toward the next port.",
      #|  "Arriving in about 18 hours, if the drive stays as set.",
      #|  "Hull at 100%.",
      #|  "Drive at 35% of full burn, with none of the 5 hands it needs.",
      #|  "Nobody is on a post yet.",
      #|  "The ship asks for hands on the drive.",
      #|]
    ),
  )
}

///|
test "a voyage from port to its first moments, in sentences" {
  let p = @ships.fleet()[0].profile
  let (_, s) = p.due(
    @core.State::initial(p.ship(seed=1), profile=p.name),
    1_800_000_000,
  )
  debug_inspect(
    where_sentences(s),
    content=(
      #|[
      #|  "In port. Departs in about 10 minutes on a 12 light-year hop.",
      #|  "Hull at 100%.",
      #|]
    ),
  )
  debug_inspect(
    you_sentences(s, "ann"),
    content=(
      #|["You join the crew when the ship departs."]
    ),
  )
  let (_, sea) = p.due(s, 1_800_000_600)
  let sea = sea.apply(Crew(crew="ann", intent=Posted(post=Drive))) catch {
    _ => panic()
  }
  debug_inspect(
    where_sentences(sea),
    content=(
      #|[
      #|  "Burning toward the next port.",
      #|  "Arriving in about 12 hours, if the drive stays as set.",
      #|  "Hull at 100%.",
      #|  "Drive at 58% of full burn, with 1 of the 5 hands it needs.",
      #|  "1 hand on the drive, 0 on the hull, 0 at crafts.",
      #|  "The ship asks for hands on the drive.",
      #|]
    ),
  )
  debug_inspect(
    you_sentences(sea, "ann"),
    content=(
      #|["You are on the drive.", "Your craft is art."]
    ),
  )
}

///|
test "happenings in sentences, from where the player stands" {
  let hs : Array[@core.Happening] = [
    Departed,
    Began(phase=Coast),
    Began(phase=Arrived),
    Docked(recruits=2),
    Opened(hazard=Breach),
    Missed(hazard=Flare),
    Landed(refit=Baffles, level=2),
    Asked(post=None),
    Took(crew="ann", post=Hull),
    Took(crew="bo", post=Craft),
    Stood(crew="bo"),
    Finished(crew="ann"),
    Spoke(line="Who will sit with me?", about=4),
  ]
  debug_inspect(
    hs.map(h => told(h, you="ann", ship="The Tigress")),
    content=(
      #|[
      #|  "The ship left port.",
      #|  "The coast began.",
      #|  "The ship arrived.",
      #|  "The ship docked, and 2 recruits joined.",
      #|  "A breach opened on the hull.",
      #|  "A flare was missed.",
      #|  "A refit landed: baffles to level 2.",
      #|  "The ship stopped asking for hands.",
      #|  "You took the hull.",
      #|  "A hand went to crafts.",
      #|  "A hand stood a watch to its end.",
      #|  "You finished a work.",
      #|  "The Tigress: Who will sit with me?",
      #|]
    ),
  )
}

///|
test "a demand interrupts, crew moves are quiet, and a line takes its cause's priority" {
  let story : Array[@core.Entry] = [
    { seq: 4, at: 0, happening: Opened(hazard=Breach), },
    { seq: 5, at: 0, happening: Took(crew="bo", post=Hull), },
    { seq: 6, at: 0, happening: Finished(crew="ann"), },
    { seq: 7, at: 0, happening: Spoke(line="Hands to the hull!", about=4), },
    { seq: 8, at: 0, happening: Spoke(line="Welcome.", about=5), },
  ]
  debug_inspect(
    story.map(e => priority(e, you="ann", story~)),
    content=(
      #|[Interrupt, Quiet, Announce, Interrupt, Announce]
    ),
  )
}

///|
test "how long ago, coarsely" {
  let at : Array[Int64] = [0, 59, 60, 7 * 60, 50 * 60, 3 * 3600, 3 * 86400]
  debug_inspect(
    at.map(ago),
    content=(
      #|[
      #|  "just now",
      #|  "just now",
      #|  "1 minute ago",
      #|  "5 minutes ago",
      #|  "50 minutes ago",
      #|  "about 3 hours ago",
      #|  "about 3 days ago",
      #|]
    ),
  )
}
