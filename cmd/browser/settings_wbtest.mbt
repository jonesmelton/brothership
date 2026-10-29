///|
test "settings round-trip through their stored names" {
  for s in [Sounds::On, Off] {
    assert_eq(Sounds::parse(s.name()), s)
  }
  for f in [Face::Book, Legible] {
    assert_eq(Face::parse(f.name()), f)
  }
  assert_eq(Sounds::parse(""), Off)
  assert_eq(Sounds::parse("junk"), Off)
  assert_eq(Face::parse(""), Book)
  assert_eq(Face::parse("junk"), Book)
  inspect(Sounds::On.name(), content="on")
  inspect(Face::Legible.name(), content="legible")
}

///|
test "a batch is one notification, high if it interrupts" {
  debug_inspect(notice("", ""), content="None")
  debug_inspect(
    notice("The coast began.", ""),
    content=(
      #|Some(("The coast began.", Normal))
    ),
  )
  debug_inspect(
    notice("", "A breach opened."),
    content=(
      #|Some(("A breach opened.", High))
    ),
  )
  debug_inspect(
    notice("The coast began.", "A breach opened."),
    content=(
      #|Some(("A breach opened. The coast began.", High))
    ),
  )
}

///|
test "each batch goes down one path only" {
  debug_inspect(
    delivery(native=true, polite="A.", assertive="B."),
    content=(
      #|Notify("B. A.", High)
    ),
  )
  debug_inspect(
    delivery(native=false, polite="A.", assertive="B."),
    content=(
      #|Regions("A.", "B.")
    ),
  )
  debug_inspect(
    delivery(native=true, polite="", assertive=""),
    content="Nothing",
  )
  debug_inspect(
    delivery(native=false, polite="", assertive=""),
    content="Nothing",
  )
}

///|
test "a cue is quiet, brief and distinct" {
  for c in [Cue::Tone, Alarm, Line] {
    let notes = c.notes()
    assert_true(!notes.is_empty())
    let mut end = 0.0
    for n in notes {
      assert_true(n.gain <= 0.2)
      assert_true(n.gain > 0.0)
      if n.at_ms + n.ms > end {
        end = n.at_ms + n.ms
      }
    }
    assert_true(end < 400.0)
  }
  assert_eq(Cue::Alarm.notes().length(), 2)
  assert_true(Cue::Tone.notes() != Cue::Line.notes())
  assert_true(Cue::Tone.notes() != Cue::Alarm.notes())
}

///|
test "only what is read aloud has a sound, and only when sounds are on" {
  let first = Told::new().merge(
    story([entry(1, Departed)]),
    you="ann",
    hear=Everything,
    ship="The Tigress",
  )
  debug_inspect(first.1.cue, content="None")
  let told = first.0
  let news = story([entry(1, Departed), entry(2, Began(phase=Coast))])
  let heard = told.merge(news, you="ann", hear=Everything, ship="The Tigress").1
  debug_inspect(heard.cue, content="Some(Tone)")
  let urgent = told.merge(news, you="ann", hear=Urgent, ship="The Tigress").1
  debug_inspect(urgent.cue, content="None")
  let nothing = told.merge(news, you="ann", hear=Nothing, ship="The Tigress").1
  debug_inspect(nothing.cue, content="None")
  let alarm = told.merge(
      story([entry(1, Departed), entry(3, Opened(hazard=Breach))]),
      you="ann",
      hear=Urgent,
      ship="The Tigress",
    ).1
  debug_inspect(alarm.cue, content="Some(Alarm)")
  let line = told.merge(
      story([
        entry(1, Departed),
        entry(2, Began(phase=Coast)),
        entry(3, Spoke(line="Steady.", about=2)),
      ]),
      you="ann",
      hear=Everything,
      ship="The Tigress",
    ).1
  debug_inspect(line.cue, content="Some(Line)")
  assert_eq(cue_for(On, Some(Alarm)), Some(Alarm))
  assert_eq(cue_for(Off, Some(Alarm)), None)
  assert_eq(cue_for(On, None), None)
}
