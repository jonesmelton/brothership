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
  live.close()
  let reopened = @store.Store::open(path)
  defer reopened.close()
  inspect(reopened.ships() == ["tigress", "scorpion", "flea"], content="true")
  inspect(
    reopened.ships().map(s => snap(reopened, s)) == snapshots,
    content="true",
  )
}
