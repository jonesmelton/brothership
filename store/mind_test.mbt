///|
async test "a minded ship takes its turn only from its mind, for the moment it weighed" {
  let store = open(":memory:")
  defer store.close()
  store.mind("tigress")
  store.advance("tigress", now=T0)
  store.advance("tigress", now=T0 + 600)
  let c = snap(store, "tigress").state.crossing().unwrap()
  debug_inspect((c.ask, c.fit.refit), content="(None, None)")
  let moment = c.moment()
  let stale = { ..moment, band: moment.band + 1L }
  let took = store.decide(
    "tigress",
    [Ask(Some(Hull))],
    moment=stale,
    now=T0 + 610,
  )
  inspect(took, content="false")
  let took = store.decide(
    "tigress",
    [Ask(Some(Hull)), Refit(Some(Coils))],
    moment~,
    now=T0 + 620,
  )
  inspect(took, content="true")
  let s = snap(store, "tigress").state
  debug_inspect(
    (s.crossing().unwrap().ask, s.crossing().unwrap().fit.refit),
    content="(Some(Hull), Some(Coils))",
  )
  guard s.leg is Underway(spoke~, ..) else { fail("not underway") }
  inspect(spoke == Some(moment), content="true")
}

///|
async test "muster appends the mind's promotions that are allowed, then docks" {
  let store = open(":memory:")
  defer store.close()
  store.mind("tigress")
  store.advance("tigress", now=T0)
  store.advance("tigress", now=T0 + 600)
  ignore(store.propose("tigress", post(1, "ann", Drive), now=T0 + 601))
  ignore(store.propose("tigress", post(2, "bo", Hull), now=T0 + 602))
  let mut now = T0 + 602
  // Steps shorter than MIND_WAIT, or the clock docks by script first.
  for _ in 0..<10_000 {
    guard @ships.arrived_at(snap(store, "tigress").state) is None else { break }
    now += 120L
    store.advance("tigress", now~)
  }
  inspect(
    snap(store, "tigress").state.leg is Underway(..),
    content="true",
  )
  let promoted = store.muster("tigress", ["bo", "ghost"], now=now + 5)
  debug_inspect(promoted, content="[(\"bo\", 1)]")
  let s = snap(store, "tigress").state
  inspect(s.leg is InPort(..), content="true")
  debug_inspect(s.ship.records.get("bo").unwrap().rank, content="Some(1)")
  debug_inspect(store.muster("tigress", ["ann"], now=now + 6), content="[]")
}
