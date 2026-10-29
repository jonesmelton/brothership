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
  assert_eq(latest_line(entries), Some("Coasting, then."))
  assert_eq(latest_line(entries[1:2].to_owned()), None)
}
