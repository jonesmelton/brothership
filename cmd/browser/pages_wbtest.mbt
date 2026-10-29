///|
test "a hash names a page, and anything else is You" {
  assert_eq(page_from_hash("#you"), You)
  assert_eq(page_from_hash("#voyage"), Voyage)
  assert_eq(page_from_hash("ship"), Ship)
  assert_eq(page_from_hash("#Voyage"), Voyage)
  assert_eq(page_from_hash(""), You)
  assert_eq(page_from_hash("#"), You)
  assert_eq(page_from_hash("#nowhere"), You)
  assert_eq(page_from_hash("#voyage/extra"), You)
}

///|
test "each page's link is its slug" {
  assert_eq(page_slug(You), "you")
  assert_eq(page_slug(Voyage), "voyage")
  assert_eq(page_slug(Ship), "ship")
  for p in all_pages {
    assert_eq(page_from_hash("#" + page_slug(p)), p)
  }
}

///|
test "viewing a page marks only its entries read, and never backwards" {
  let v : Viewed = { you: 3L, voyage: 5L, ship: 7L, }
  assert_eq(v.mark(Voyage, 9L), { you: 3L, voyage: 9L, ship: 7L, })
  assert_eq(v.mark(Voyage, 2L), v)
  assert_eq(v.get(You), 3L)
  assert_eq(v.get(Ship), 7L)
}

///|
test "viewed seqs round-trip through storage and survive junk" {
  let v : Viewed = { you: 3L, voyage: 5L, ship: 7L, }
  assert_eq(v.name(), "3,5,7")
  assert_eq(Viewed::parse("3,5,7"), Some(v))
  assert_eq(Viewed::parse(""), None)
  assert_eq(Viewed::parse("3,5"), None)
  assert_eq(Viewed::parse("a,b,c"), None)
}

///|
test "unread counts entries on the page past what was viewed" {
  let entries = [
    entry(1, Departed),
    entry(2, Took(crew="bo", post=Hull)),
    entry(3, Opened(hazard=Breach)),
    entry(4, Took(crew="cy", post=Drive)),
  ]
  let hull_only = (e : @core.Entry) => e.happening is Took(_)
  assert_eq(unread(entries, 0L, hull_only), 2)
  assert_eq(unread(entries, 2L, hull_only), 1)
  assert_eq(unread(entries, 4L, hull_only), 0)
  assert_eq(unread(entries, 0L, _ => false), 0)
  assert_eq(unread([], 0L, _ => true), 0)
}

///|
test "going to a page marks it read and drops the last effect" {
  let model : Model = {
    ..aboard(),
    told: {
      entries: [entry(4, Departed), entry(6, Began(phase=Coast))],
      arrived: Some(6L),
      speaking: false,
      thinking: false,
    },
    effect: ["The ship will arrive sooner."],
  }
  let there = model.goto(Voyage)
  assert_eq(there.page, Voyage)
  assert_eq(there.effect, [])
  assert_eq(there.viewed.voyage, 6L)
  assert_eq(there.viewed.you, model.viewed.you)
  // Staying put changes nothing, so the heading is not focused again.
  assert_true(there.goto(Voyage) == there)
}

///|
test "an effect is kept and spoken, unless the player wants silence" {
  let lines = ["Breach will be met.", "Regard rises."]
  let (said, _) = aboard().with_effect(lines)
  assert_eq(said.effect, lines)
  assert_eq(said.said.polite, "Breach will be met. Regard rises.")
  assert_eq(said.said.count, 1)
  let (quiet, _) = { ..aboard(), hear: Nothing, }.with_effect(lines)
  let (native, _) = { ..aboard(), notify: true, }.with_effect(lines)
  assert_eq(native.said.polite, "")
  assert_eq(native.said.count, 0)
  assert_eq(quiet.effect, lines)
  assert_eq(quiet.said.polite, "")
  assert_eq(quiet.said.count, 0)
  // The next proposal replaces it.
  assert_eq(said.with_effect(["Nothing changed."]).0.effect, [
    "Nothing changed.",
  ])
}

///|
test "a stood watch offers the same length again, capped at the longest offered" {
  let stood = [
    entry(1, Departed),
    entry(2, Took(crew="ann", post=Hull)),
    entry(3, Stood(crew="ann")),
  ]
  assert_eq(reup(stood, "ann", 4L), Some(4L))
  assert_eq(reup(stood, "ann", 24L), Some(12L))
  assert_eq(reup(stood, "ann", 0L), None)
}

///|
test "a watch is not offered again unless it was stood" {
  // Someone else's watch.
  assert_eq(
    reup([entry(1, Departed), entry(3, Stood(crew="bo"))], "ann", 4L),
    None,
  )
  // A post change since.
  assert_eq(
    reup(
      [
        entry(1, Departed),
        entry(3, Stood(crew="ann")),
        entry(4, Took(crew="ann", post=Drive)),
      ],
      "ann",
      4L,
    ),
    None,
  )
  assert_eq(
    reup(
      [
        entry(1, Departed),
        entry(3, Stood(crew="ann")),
        entry(4, Left(crew="ann")),
      ],
      "ann",
      4L,
    ),
    None,
  )
  // A watch stood in an earlier crossing.
  assert_eq(
    reup(
      [entry(1, Departed), entry(3, Stood(crew="ann")), entry(9, Departed)],
      "ann",
      4L,
    ),
    None,
  )
  // Nothing stood yet: a watch still running, or never started.
  assert_eq(reup([entry(1, Departed)], "ann", 4L), None)
  assert_eq(reup([], "ann", 4L), None)
}

///|
test "the re-up button says what it does" {
  assert_eq(reup_label(1L), "Stand 1 more hour")
  assert_eq(reup_label(4L), "Stand 4 more hours")
}

///|
test "a bar fills in thousandths, clamped" {
  assert_eq(fill_of(0L, 100L), 0L)
  assert_eq(fill_of(25L, 100L), 250L)
  assert_eq(fill_of(1L, 3L), 333L)
  assert_eq(fill_of(150L, 100L), 1000L)
  assert_eq(fill_of(-5L, 100L), 0L)
  assert_eq(fill_of(5L, 0L), 0L)
}

///|
test "the ledger is read back, and a bad one is dropped" {
  let l : @words.Ledger = {
    at: 9L,
    regard: 2L,
    works: 1L,
    crossings: 3L,
    rank: Some(1L),
  }
  assert_eq(parse_ledger(l.to_json().stringify()), Some(l))
  assert_eq(parse_ledger(""), None)
  assert_eq(parse_ledger("{\"at\":"), None)
  assert_eq(parse_ledger("[]"), None)
}
