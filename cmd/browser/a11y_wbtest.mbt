///|
fn listing(id : String, name : String) -> @core.Listing {
  {
    id,
    name,
    crossings: 0,
    whereabouts: InPort(departs=0),
    run: 0,
    officers: 0,
  }
}

///|
fn aboard() -> Model {
  {
    officer: "ann",
    now: 0L,
    ships: [listing("tigress", "EF-147 The Tigress")],
    ship: Some("tigress"),
    joining: false,
    left: None,
    seen: None,
    page: You,
    settings: false,
    viewed: { you: 0L, voyage: 0L, ship: 0L, },
    ledger: None,
    last_watch: 0L,
    effect: [],
    told: Told::new(),
    hear: Everything,
    sounds: Off,
    face: Book,
    notify: false,
    said: { polite: "", assertive: "", count: 0, },
    sync: Loading,
  }
}

///|
test "focus follows the control that disappears" {
  let standing : @core.Order = { phase: Coast, post: Drive, }
  assert_eq(focus_after(@core.Watched(ticks=3600L), None), Some("watch"))
  assert_eq(
    focus_after(@core.Ordered(order=None), Some(standing)),
    Some("order-coast"),
  )
  assert_eq(focus_after(@core.Left, None), Some("post"))
  assert_eq(focus_after(@core.Made, None), Some("craft"))
  assert_eq(focus_after(@core.Posted(post=Drive), Some(standing)), None)
  assert_eq(focus_after(@core.Crafted(craft=Artist), None), None)
  assert_eq(focus_after(@core.Refitting(refit=Some(@core.Baffles)), None), None)
  assert_eq(focus_after(@core.Ordered(order=None), None), None)
}

///|
test "the page title names the ship, or the game" {
  assert_eq(page_title(aboard()), "EF-147 The Tigress")
  assert_eq(page_title({ ..aboard(), ship: None, }), "brothership")
  assert_eq(page_title({ ..aboard(), ships: [], }), "brothership")
  assert_eq(page_title({ ..aboard(), settings: true, }), "Settings")
}

///|
test "a compact rank reads as the full rank, never the abbreviation" {
  assert_eq(reading(rank_compact_parts(3L)), "Lieutenant commander")
  assert_eq(reading(rank_compact_parts(0L)), "Ensign")
  assert_eq(reading(rank_compact_parts(4L)), "Commander")
}

///|
test "a compact rank hides its abbreviation and insignia" {
  let hidden = rank_compact_parts(3L).filter(p => p.hidden).map(p => p.text)
  assert_eq(hidden, ["LCDR", "\u{25cf}\u{25cf}\u{25cf}"])
}

///|
test "the rank line reads as the full title and hides the insignia" {
  assert_eq(reading(rank_line_parts(1L)), "Lieutenant junior grade")
  assert_eq(reading(rank_line_parts(4L)), "Commander")
  let hidden = rank_line_parts(4L).filter(p => p.hidden).map(p => p.text)
  assert_eq(hidden, ["\u{2605}"])
}

///|
test "an officer never aboard holds the rank of an ensign" {
  let s = @core.State::initial(
    @ships.fleet()[0].profile.ship(seed=1L),
    profile="tigress",
  )
  assert_eq(s.rank("stranger"), 0L)
}
