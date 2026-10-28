///|
/// The first tick of every test, in Unix seconds.
const T0 : Int64 = 1_800_000_000L

///|
async fn open(path : String) -> @store.Store {
  @store.Store::open(path, ship=@ships.profiles()[1], seed=1)
}

///|
fn post(id : Int64, crew : String, post : @core.Post) -> @core.Proposal {
  { id, crew, intent: Posted(post~), }
}

///|
fn leg_name(s : @core.Snapshot) -> String {
  match s.state.leg {
    InPort(_) => "in port"
    Underway(crossing~, ..) => "underway, t=\{crossing.t}"
  }
}

///|
async test "propose ticks, validates, persists, and lets the ship respond" {
  let store = open(":memory:")
  defer store.close()
  inspect(store.snapshot().seq, content="0")
  debug_inspect(
    store.propose(post(1, "ann", Drive), now=T0),
    content=(
      #|Refused(
      #|  id=1,
      #|  reason=NotUnderway(event=Crew(crew="ann", intent=Posted(post=Drive))),
      #|  snapshot={
      #|    seq: 1,
      #|    state: {
      #|      at: 1800000000,
      #|      ship: {
      #|        values: { drive: 1, hull: 3, craft: 2 },
      #|        fit: {
      #|          needed: 5,
      #|          wear: 24000,
      #|          repair: 32000,
      #|          baffles: 0,
      #|          plating: 0,
      #|          injectors: 0,
      #|          coils: 0,
      #|          refit: None,
      #|          progress: 0,
      #|        },
      #|        hull: 1000000000,
      #|        records: {},
      #|        recruits: 0,
      #|        toward_recruit: 0,
      #|        crossings: 0,
      #|        seed: 1,
      #|      },
      #|      leg: InPort(since=1800000000),
      #|    },
      #|  },
      #|)
    ),
  )
  inspect(store.wake(), content="1800000600")
  let receipt = store.propose(post(2, "ann", Drive), now=T0 + 600)
  inspect(receipt is Accepted(_), content="true")
  inspect(leg_name(store.snapshot()), content="underway, t=0")
  inspect(receipt.snapshot() == store.snapshot(), content="true")
  // The refused proposal's tick, then this one's tick, the departure, the
  // ship's refit and ask, and the crew's post. Crew moving is no moment, so
  // the ship does not speak again.
  inspect(store.snapshot().seq, content="6")
  inspect(store.snapshot().state.crossing().unwrap().count(Drive), content="1")
}

///|
async test "a proposal at an earlier wall clock appends no tick" {
  let store = open(":memory:")
  defer store.close()
  store.advance(now=T0)
  store.advance(now=T0 + 600)
  let before = store.snapshot()
  ignore(store.propose(post(1, "ann", Hull), now=T0 + 100))
  let after = store.snapshot()
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
  live.advance(now~)
  while live.snapshot().state.ship.crossings < 2L && wakes < 10_000 {
    // Crew act between the ship's instants, as players would.
    let i = wakes % 3
    ignore(live.propose(post(id, crew[i], posts[wakes / 3 % 3]), now~))
    id += 1L
    now = live.wake().min(now + 3600L).max(now + 1L)
    live.advance(now~)
    wakes += 1
  }
  inspect(live.snapshot().state.ship.crossings, content="2")
  let snapshot = live.snapshot()
  live.close()
  let reopened = open(path)
  defer reopened.close()
  inspect(reopened.snapshot() == snapshot, content="true")
}
