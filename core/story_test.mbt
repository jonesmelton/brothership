///|
/// Apply `events` from `s`, collecting each one's happenings in order.
fn told(
  s : @core.State,
  events : Array[@core.Event],
) -> (Array[@core.Happening], @core.State) {
  let out = []
  let mut s = s
  for e in events {
    let next = s.apply(e) catch { _ => panic() }
    out.append(@core.happenings(s, e, next))
    s = next
  }
  (out, s)
}

///|
test "a crossing told from departure to docking" {
  let start = ready(ship())
  let (said, s) = told(start, [
    Departed(plan=plan20()),
    Asked(post=Some(Drive)),
    Asked(post=Some(Drive)),
    Crew(crew="ann", intent=Posted(post=Drive)),
    Crew(crew="ann", intent=Watched(ticks=3600)),
    Tick(at=DEPART_AT + 6 * 3600),
  ])
  debug_inspect(
    said,
    content=(
      #|[
      #|  Departed,
      #|  Asked(post=Some(Drive)),
      #|  Signed(crew="ann"),
      #|  Took(crew="ann", post=Drive),
      #|  Began(phase=Coast),
      #|  Missed(hazard=Flare),
      #|  Missed(hazard=Breach),
      #|  Stood(crew="ann"),
      #|]
    ),
  )
  let c = s.crossing().unwrap()
  let (said, _) = told(s, [
    Tick(at=s.at + c.forecast().unwrap()),
    Docked(stores=0),
  ])
  debug_inspect(
    said,
    content=(
      #|[
      #|  Began(phase=Approach),
      #|  Began(phase=Arrived),
      #|  Docked(
      #|    recruits=0,
      #|    landing={
      #|      leg: 0,
      #|      aboard: 53526,
      #|      works: 0,
      #|      plan: {
      #|        burn: 10779000000,
      #|        coast: 18838000000,
      #|        eta_rate: 1308460,
      #|        coast_rate: 760500,
      #|      },
      #|    },
      #|  ),
      #|]
    ),
  )
}

///|
test "a ship's line is a happening and changes nothing else" {
  let s = underway(plan20(), ship())
  let e : @core.Event = Spoke(line="Who will sit with me?", about=7)
  let next = s.apply(e) catch { _ => panic() }
  assert_eq(next, s)
  debug_inspect(
    @core.happenings(s, e, next),
    content=(
      #|[Spoke(line="Who will sit with me?", about=7)]
    ),
  )
}

///|
test "making banked work is told, and finishing and landing follow from it" {
  let start = ready(ship())
  let (_, s) = told(start, [
    Departed(plan=plan20()),
    Crew(crew="ann", intent=Posted(post=Craft)),
    Crew(crew="ann", intent=Crafted(craft=Artist)),
    Crew(crew="bo", intent=Posted(post=Craft)),
    Crew(crew="bo", intent=Crafted(craft=Engineer)),
    Crew(crew="cy", intent=Posted(post=Craft)),
    Crew(crew="cy", intent=Crafted(craft=Engineer)),
    Refitting(refit=Some(Baffles)),
    Tick(at=DEPART_AT + 7 * 3600),
  ])
  let (said, _) = told(s, [
    Crew(crew="ann", intent=Made),
    Crew(crew="bo", intent=Made),
    Crew(crew="cy", intent=Made),
  ])
  debug_inspect(
    said,
    content=(
      #|[
      #|  Made(crew="ann", craft=Artist, units=520128, percent=129),
      #|  Finished(crew="ann"),
      #|  Made(crew="bo", craft=Engineer, units=554400, percent=110),
      #|  Landed(refit=Baffles, level=1),
      #|  Made(crew="cy", craft=Engineer, units=554400, percent=110),
      #|  Landed(refit=Baffles, level=2),
      #|]
    ),
  )
  let (left, _) = told(s, [Crew(crew="ann", intent=Left)])
  debug_inspect(
    left,
    content=(
      #|[Left(crew="ann"), Finished(crew="ann")]
    ),
  )
}

///|
test "a launch told: the ask, then the stores loaded" {
  let (said, _) = told(loading(28_800, [Drive]), [
    Asked(post=Some(Hull)),
    Tick(at=DEPART_AT + 1800),
    Tick(at=DEPART_AT + 3600),
    Tick(at=DEPART_AT + 3700),
  ])
  debug_inspect(
    said,
    content=(
      #|[Asked(post=Some(Hull)), Loaded]
    ),
  )
}
