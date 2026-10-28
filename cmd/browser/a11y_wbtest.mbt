///|
fn listing(id : String, name : String) -> @core.Listing {
  { id, name, }
}

///|
fn aboard() -> Model {
  {
    officer: "ann",
    now: 0L,
    ships: [listing("tigress", "EF-147 The Tigress")],
    ship: Some("tigress"),
    seen: None,
    page: You,
    viewed: { you: 0L, voyage: 0L, ship: 0L, },
    ledger: None,
    last_watch: 0L,
    effect: [],
    told: Told::new(),
    hear: Everything,
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
}
