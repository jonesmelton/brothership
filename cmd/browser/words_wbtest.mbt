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
      #|  "Drive at 58% of full burn, with 1 of 5 hands it needs.",
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
  debug_inspect(
    news(s, sea, "ann"),
    content=(
      #|["The ship left port."]
    ),
  )
  let (_, later) = p.due(sea, 1_800_000_600 + 6 * 3600)
  debug_inspect(
    news(sea, later, "ann"),
    content=(
      #|["The coast began.", "A flare was missed.", "A breach was missed."]
    ),
  )
}
