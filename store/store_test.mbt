///|
/// The first tick of every test, in Unix seconds.
const T0 : Int64 = 1_800_000_000L

///|
/// A store with the whole fleet in service.
async fn open(path : String) -> @store.Store {
  let store = @store.Store::open(path)
  for berth in @ships.fleet() {
    store.commission(berth)
  }
  store
}

///|
fn post(id : Int64, crew : String, post : @core.Post) -> @core.Proposal {
  { id, crew, intent: Posted(post~), }
}

///|
fn snap(store : @store.Store, ship : String) -> @core.Snapshot {
  store.snapshot(ship).unwrap()
}

///|
fn leg_name(s : @core.Snapshot) -> String {
  match s.state.leg {
    InPort(_) => "in port"
    Underway(crossing~, ..) => "underway, t=\{crossing.t}"
  }
}

///|
async test "commissioning puts each ship in service once" {
  let store = open(":memory:")
  defer store.close()
  debug_inspect(
    store.ships(),
    content=(
      #|["tigress", "scorpion", "flea"]
    ),
  )
  inspect(snap(store, "tigress").seq, content="1")
  inspect(
    snap(store, "flea").state.profile,
    content=(
      #|EF-287 The Flea on the Drum
    ),
  )
  store.commission(@ships.fleet()[0])
  inspect(snap(store, "tigress").seq, content="1")
  debug_inspect(store.snapshot("nobody"), content="None")
}

///|
async test "propose ticks, validates, persists, and lets the ship respond" {
  let store = open(":memory:")
  defer store.close()
  let refused = store.propose("tigress", post(1, "ann", Drive), now=T0).unwrap()
  debug_inspect(refused is Refused(reason=NotUnderway(_), ..), content="true")
  // The refusal still wrote the ship's first tick.
  inspect(snap(store, "tigress").state.at, content="1800000000")
  let receipt = store
    .propose("tigress", post(2, "ann", Drive), now=T0 + 600)
    .unwrap()
  inspect(receipt is Accepted(_), content="true")
  inspect(leg_name(snap(store, "tigress")), content="underway, t=0")
  inspect(receipt.snapshot() == snap(store, "tigress"), content="true")
  inspect(
    snap(store, "tigress").state.crossing().unwrap().count(Drive),
    content="1",
  )
  // Other ships are untouched.
  inspect(snap(store, "flea").state.at, content="0")
  debug_inspect(
    store.propose("nobody", post(3, "ann", Drive), now=T0),
    content="None",
  )
}

///|
async test "a proposal at an earlier wall clock appends no tick" {
  let store = open(":memory:")
  defer store.close()
  store.advance("scorpion", now=T0)
  store.advance("scorpion", now=T0 + 600)
  let before = snap(store, "scorpion")
  ignore(store.propose("scorpion", post(1, "ann", Hull), now=T0 + 100))
  let after = snap(store, "scorpion")
  inspect(after.state.at == before.state.at, content="true")
  inspect(after.seq - before.seq, content="1")
}

///|
async test "a store reopened from its file equals the live one" {
  let dir = @fs.tmpdir(prefix="brothership-store-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/game.sqlite"
  let live = open(path)
  let crew = ["ann", "bo", "cy"]
  let posts : Array[@core.Post] = [Drive, Hull, Craft]
  let mut now = T0
  let mut id = 1L
  let mut wakes = 0
  for ship in live.ships() {
    live.advance(ship, now~)
  }
  while snap(live, "tigress").state.ship.crossings < 2L && wakes < 10_000 {
    // Crew act between the ships' instants, as players would.
    let i = wakes % 3
    ignore(
      live.propose("tigress", post(id, crew[i], posts[wakes / 3 % 3]), now~),
    )
    ignore(live.propose("flea", post(id, crew[i], posts[wakes % 3]), now~))
    id += 1L
    let mut next = now + 3600L
    for berth in @ships.fleet() {
      next = next.min(berth.next_advance(snap(live, berth.id).state, now))
    }
    now = next
    for ship in live.ships() {
      live.advance(ship, now~)
    }
    wakes += 1
  }
  inspect(snap(live, "tigress").state.ship.crossings, content="2")
  let snapshots = live.ships().map(s => snap(live, s))
  let stories = Map::from_array(
    live.ships().map(s => (s, live.story(s, after=0))),
  )
  inspect(stories["tigress"].unwrap().length() > 10, content="true")
  live.close()
  let reopened = @store.Store::open(path)
  defer reopened.close()
  inspect(reopened.ships() == ["tigress", "scorpion", "flea"], content="true")
  inspect(
    reopened.ships().map(s => snap(reopened, s)) == snapshots,
    content="true",
  )
  for ship in live.ships() {
    assert_eq(reopened.story(ship, after=0), stories[ship], msg=ship)
  }
}

///|
fn kinds(entries : Array[@core.Entry]) -> Array[@core.Happening] {
  entries.map(e => e.happening)
}

///|
async test "the story tells what happened, after a given seq" {
  let store = open(":memory:")
  defer store.close()
  ignore(store.propose("tigress", post(1, "ann", Drive), now=T0))
  ignore(store.propose("tigress", post(2, "ann", Drive), now=T0 + 600))
  let story = store.story("tigress", after=0).unwrap()
  debug_inspect(
    kinds(story),
    content=(
      #|[Departed, Asked(post=Some(Drive)), Took(crew="ann", post=Drive)]
    ),
  )
  let first = story[0].seq
  inspect(
    store.story("tigress", after=first).unwrap().length() == story.length() - 1,
    content="true",
  )
  inspect(story.iter().all(e => e.at == T0 + 600), content="true")
  debug_inspect(store.story("nobody", after=0), content="None")
}

///|
async test "a ship's line is appended after its tick and joins the story" {
  let store = open(":memory:")
  defer store.close()
  store.advance("tigress", now=T0)
  store.advance("tigress", now=T0 + 600)
  let about = store.story("tigress", after=0).unwrap()[0].seq
  store.speak("tigress", line="Who will sit with me?", about~, now=T0 + 700)
  let last = store.story("tigress", after=0).unwrap().last().unwrap()
  debug_inspect(
    last.happening,
    content=(
      #|Spoke(line="Who will sit with me?", about=6)
    ),
  )
  inspect(last.at, content="1800000700")
  inspect(last.seq == snap(store, "tigress").seq, content="true")
}

///|
async test "a promotion row replays and joins the story" {
  let dir = @fs.tmpdir(prefix="brothership-store-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/game.sqlite"
  let live = open(path)
  let mut now = T0
  let mut id = 1L
  live.advance("tigress", now~)
  let promoted = () => {
    live
    .story("tigress", after=0)
    .unwrap()
    .iter()
    .any(e => e.happening is Promoted(..))
  }
  for _ in 0..<50_000 {
    guard !promoted() else { break }
    ignore(live.propose("tigress", post(id, "ann", Drive), now~))
    id += 1L
    now = @ships.fleet()[0].next_advance(snap(live, "tigress").state, now)
    live.advance("tigress", now~)
  }
  let story = live.story("tigress", after=0).unwrap()
  let at = story.search_by(e => e.happening is Promoted(..)).unwrap()
  debug_inspect(
    story[at].happening,
    content=(
      #|Promoted(
      #|  crew="ann",
      #|  rank=1,
      #|  tally={
      #|    drive: 154436,
      #|    hull: 0,
      #|    craft: 0,
      #|    regard: 166284,
      #|    work: 0,
      #|    watches_stood: 0,
      #|    watches_broken: 0,
      #|  },
      #|)
    ),
  )
  guard story[at + 1].happening is Docked(..) else {
    fail("expected docking right after the promotion")
  }
  let snapshot = snap(live, "tigress")
  assert_eq(snapshot.state.ship.records["ann"].rank, Some(1L))
  live.close()
  let reopened = @store.Store::open(path)
  defer reopened.close()
  inspect(snap(reopened, "tigress") == snapshot, content="true")
  assert_eq(reopened.story("tigress", after=0), Some(story))
}
