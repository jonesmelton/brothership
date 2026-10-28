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
  let start = @core.State::initial(ship(), profile="test").apply(
    Tick(at=DEPART_AT),
  ) catch {
    _ => panic()
  }
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
      #|  Took(crew="ann", post=Drive),
      #|  Began(phase=Coast),
      #|  Missed(hazard=Flare),
      #|  Missed(hazard=Breach),
      #|  Stood(crew="ann"),
      #|]
    ),
  )
  let c = s.crossing().unwrap()
  let (said, _) = told(s, [Tick(at=s.at + c.forecast().unwrap()), Docked])
  debug_inspect(
    said,
    content=(
      #|[Began(phase=Approach), Began(phase=Arrived), Docked(recruits=0)]
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
