///|
async test "a hail waits for its ship until it is answered or falls silent" {
  let store = open(":memory:")
  defer store.close()
  store.advance("tigress", now=T0)
  debug_inspect(store.hail("nobody", "Dust ahead.", now=T0), content="None")
  let first = store.hail("tigress", "Dust ahead.", now=T0 + 1).unwrap()
  let second = store.hail("tigress", "Cold tonight.", now=T0 + 2).unwrap()
  let other = store.hail("scorpion", "Dust ahead.", now=T0 + 3).unwrap()
  assert_eq(store.open_hails("tigress").map(h => h.id), [first, second])
  store.speak(
    "tigress",
    line=cleared("Dust ahead, loves."),
    about=-1,
    now=T0 + 10,
    hail=first,
  )
  let spoke = snap(store, "tigress").seq
  store.silence(second, reason="kept quiet", now=T0 + 11)
  assert_eq(store.open_hails("tigress"), [])
  assert_eq(store.open_hails("scorpion").map(h => h.id), [other])
  let outcomes : Array[(String, String, Int64, @store.Outcome)] = [
    ("scorpion", "Dust ahead.", T0 + 3, Open),
    (
      "tigress",
      "Cold tonight.",
      T0 + 2,
      Silent(reason="kept quiet", at=T0 + 11),
    ),
    ("tigress", "Dust ahead.", T0 + 1, Spoke(seq=spoke, at=T0 + 10)),
  ]
  assert_eq(
    store.hails().map(h => (h.ship, h.text, h.sent_at, h.outcome)),
    outcomes,
  )
}

///|
async test "hails survive a reopen" {
  let dir = @fs.tmpdir(prefix="brothership-hail-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/game.sqlite"
  let store = open(path)
  let id = store.hail("tigress", "Dust ahead.", now=T0).unwrap()
  store.close()
  let reopened = open(path)
  defer reopened.close()
  assert_eq(reopened.open_hails("tigress").map(h => h.id), [id])
}
