///|
/// Commands are not run in these tests.
fn quiet() -> @rabbita.Emit[Msg] {
  @cmd.Emit(_ => @rabbita.none)
}

///|
/// The Tigress in port, with `officers` signed on.
fn port_snapshot(officers : Array[String]) -> @core.Snapshot {
  let mut s = @core.State::initial(
    @ships.fleet()[0].profile.ship(seed=1L),
    profile="EF-147 The Tigress",
  ).apply(Tick(at=1_800_000_000L)) catch {
    _ => panic()
  }
  for crew in officers {
    s = s.apply(Crew(crew~, intent=Signed)) catch { _ => panic() }
  }
  { seq: 10, state: s, }
}

///|
fn step(model : Model, msg : Msg) -> Model {
  update(model, msg, quiet()).0
}

///|
test "choosing a ship signs on once its snapshot loads" {
  // As `Choose` leaves it; `board` reads `localStorage`, which tests lack.
  let chose = { ..aboard(), joining: true, }
  let loaded = step(chose, Loaded("tigress", Ok(port_snapshot([]))))
  guard loaded.sync is Ready(sync) else { fail("not ready") }
  assert_false(loaded.joining)
  debug_inspect(sync.in_flight().map(p => p.intent), content="Some(Signed)")
  assert_true(sync.predicted().officers.contains("ann"))
  // Aboard another ship: the server refuses, and the player chooses again.
  let receipt : @core.Receipt = Refused(
    id=sync.in_flight().unwrap().id,
    reason=AboardAnother(ship="flea"),
    snapshot=port_snapshot([]),
  )
  let refused = step(loaded, Settled("tigress", Ok(receipt)))
  assert_eq(refused.ship, None)
  assert_eq(refused.left, Some("EF-147 The Tigress"))
}

///|
test "a player discharged while away is shown the ships to choose from" {
  let still = step(aboard(), Loaded("tigress", Ok(port_snapshot(["ann"]))))
  assert_eq(still.ship, Some("tigress"))
  let gone = step(aboard(), Loaded("tigress", Ok(port_snapshot(["bo"]))))
  assert_eq(gone.ship, None)
  assert_eq(gone.left, Some("EF-147 The Tigress"))
}
