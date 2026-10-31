///|
fn entry(seq : Int64, h : @core.Happening) -> @core.Entry {
  { seq, at: 1_800_000_000, happening: h, }
}

///|
fn story(entries : Array[@core.Entry]) -> @core.Story {
  { entries, speaking: false, thinking: false, }
}

///|
test "the first story of a visit is not read aloud, later news is" {
  let first = story([entry(4, Departed), entry(5, Took(crew="bo", post=Hull))])
  let (told, heard) = Told::new().merge(
    first,
    you="ann",
    hear=Everything,
    ship="The Tigress",
  )
  inspect(heard.polite + heard.assertive, content="")
  debug_inspect(told.arrived, content="Some(5)")
  let later = story([
    entry(5, Took(crew="bo", post=Hull)),
    entry(9, Opened(hazard=Breach)),
    entry(10, Spoke(line="Hands to the hull!", about=9)),
    entry(11, Began(phase=Coast)),
    entry(12, Took(crew="cy", post=Drive)),
  ])
  let (told, heard) = told.merge(
    later,
    you="ann",
    hear=Everything,
    ship="The Tigress",
  )
  inspect(told.entries.length(), content="6")
  inspect(
    heard.assertive,
    content="A breach opened on the hull. The Tigress: Hands to the hull!",
  )
  inspect(heard.polite, content="The coast began.")
  let (_, heard) = Told::new().merge(
    first,
    you="ann",
    hear=Urgent,
    ship="The Tigress",
  ).0.merge(later, you="ann", hear=Urgent, ship="The Tigress")
  inspect(heard.polite, content="")
  inspect(
    heard.assertive,
    content="A breach opened on the hull. The Tigress: Hands to the hull!",
  )
}

///|
test "a long announcement points to the log" {
  inspect(
    capped(["One.", "Two.", "Three.", "Four.", "Five."]),
    content="One. Two. Three. And 2 more in the log.",
  )
}

///|
test "while you were away covers the absence, not this visit" {
  let (told, _) = Told::new().merge(
    story([
      entry(3, Departed),
      entry(4, Took(crew="bo", post=Hull)),
      entry(6, Missed(hazard=Flare)),
    ]),
    you="ann",
    hear=Everything,
    ship="The Tigress",
  )
  let (told, _) = told.merge(
    story([entry(8, Began(phase=Coast))]),
    you="ann",
    hear=Everything,
    ship="The Tigress",
  )
  debug_inspect(
    told.away(Some(3), you="ann", ship="The Tigress"),
    content=(
      #|["A flare was missed."]
    ),
  )
  debug_inspect(
    told.away(Some(6), you="ann", ship="The Tigress"),
    content=(
      #|["Nothing new since your last visit."]
    ),
  )
  debug_inspect(
    told.away(None, you="ann", ship="The Tigress"),
    content=(
      #|["This is your first visit to this ship."]
    ),
  )
}

///|
test "the stage holds the latest line, and nothing before the first" {
  let entries = [
    entry(1, Spoke(line="Hands to the hull!", about=0)),
    entry(2, Began(phase=Coast)),
    entry(3, Spoke(line="Coasting, then.", about=2)),
    entry(4, Took(crew="cy", post=Drive)),
  ]
  assert_eq(latest_line(entries).map(e => e.seq), Some(3L))
  assert_eq(latest_line(entries[1:2].to_owned()).map(e => e.seq), None)
}

///|
test "an arrival is one short batch and the roll call stays in the log" {
  let landing : @core.Landing = {
    leg: 0,
    from: None,
    to: None,
    aboard: 50400,
    works: 3,
    plan: { burn: 0, coast: 0, eta_rate: 0, coast_rate: 0, },
  }
  let tally : @core.Tally = {
    drive: 0,
    hull: 0,
    craft: 0,
    regard: 0,
    work: 0,
    watches_stood: 0,
    watches_broken: 0,
    served: 0,
  }
  let first = story([entry(4, Departed)])
  let (told, _) = Told::new().merge(
    first,
    you="ann",
    hear=Everything,
    ship="The Tigress",
  )
  let arrival = story([
    entry(5, Began(phase=Arrived)),
    entry(6, Promoted(crew="bo", rank=1, tally~)),
    entry(7, Promoted(crew="cy", rank=1, tally~)),
    entry(8, Promoted(crew="di", rank=2, tally~)),
    entry(9, Promoted(crew="ann", rank=2, tally~)),
    entry(10, Docked(recruits=1, landing~)),
  ])
  let (_, heard) = told.merge(
    arrival,
    you="ann",
    hear=Everything,
    ship="The Tigress",
  )
  inspect(
    heard.polite,
    content=(
      #|The ship arrived. You were promoted to lieutenant. The ship docked, and 1 recruit joined.
    ),
  )
}
