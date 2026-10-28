// Flies one ship through a crossing in memory, with four scripted officers
// aboard, and prints each choice its mind makes and each line it writes, as
// the server would. For hearing a ship's voice and character before it
// flies. Run from the repository root.
//
//   moon run cmd/speak -- [--replay] [--mind M] [--writer M] [ship]
//
// `ship` is a berth id from the fleet (default: tigress), and needs
// approved captain.md and voice.md. Replies are cached in .cache/llm, so a
// rerun is free; --replay uses only the cache.

///|
const START : Int64 = 1_800_000_000L

///|
async fn main {
  let args = @env.args()[1:].to_owned()
  let mode : @cache.Mode = if args.contains("--replay") { Replay } else { Live }
  let flag = (name : String) => args.search(name).bind(i => args.get(i + 1))
  let model = flag("--mind").unwrap_or("meta:muse-spark-1.3-contributor")
  let writer = flag("--writer").unwrap_or(model)
  let id = args
    .iter()
    .find_first(a => {
      !a.has_prefix("--") &&
      flag("--mind") != Some(a) &&
      flag("--writer") != Some(a)
    })
    .unwrap_or("tigress")
  guard @ships.fleet().iter().find_first(b => b.id == id) is Some(berth) else {
    fail("no ship \{id} in the fleet")
  }
  guard berth.profile.title is Some(title) &&
    @speech.Voice::load(content="content", title) is Some(voice) else {
    fail("\{id} has no approved captain.md and voice.md")
  }
  let key = match (mode, @speech.meta_key()) {
    (Replay, _) => ""
    (Live, Some(key)) => key
    (Live, None) =>
      fail("set MODEL_API_KEY or write ~/.config/brothership/meta-api.key")
  }
  let backend = @cache.cached(
    @speech.meta_backend(key),
    dir=".cache/llm",
    mode~,
  )
  let speech = @speech.Speech::load(
    content="content",
    model=writer,
    gate_model="meta:muse-spark-1.3-contributor",
  )
  let store = @store.Store::open(":memory:")
  defer store.close()
  store.commission(berth)
  store.mind(id)
  let mind = @mind.Mind::new(
    id,
    berth.profile,
    voice,
    @mind.Prompts::load(content="content"),
    model~,
    backend,
  )
  let speaker = @speech.Speaker::new(id, voice, speech, backend, from=0, thoughts=() => {
    mind.thoughts()
  })
  let mut now = START
  let mut shown = 0L
  let mut departed : Int64? = None
  let mut proposal = 0L
  // One crossing: until the ship docks once.
  while store.snapshot(id).unwrap().state.ship.crossings < 1L {
    store.advance(id, now~)
    mind.step(store, clock=() => now)
    let s = store.snapshot(id).unwrap().state
    if s.leg is Underway(..) && departed is None {
      departed = Some(now)
    }
    if departed is Some(start) {
      for pair in officers(s, now, start) {
        proposal += 1L
        ignore(
          store.propose(
            id,
            { id: proposal, crew: pair.0, intent: pair.1, },
            now~,
          ),
        )
      }
    }
    speaker.step(store, clock=() => now)
    for e in store.story(id, after=shown).unwrap() {
      let hours = (e.at - START) / 3600L
      let minutes = (e.at - START) % 3600L / 60L
      let line = match e.happening {
        Spoke(line~, ..) => "  \{voice.epithet}: \{line}"
        Took(..) | Left(_) | Stood(_) | Finished(_) => continue
        h =>
          "\{hours}h\{minutes}m \{@words.told(h, you="", ship=voice.epithet)}"
      }
      println(line)
      shown = e.seq
    }
    // At least every 10 minutes, so the officers act between instants.
    now = berth
      .next_advance(store.snapshot(id).unwrap().state, now, minded=true)
      .min(now + 600L)
  }
}

///|
/// What four officers do at `now`, given the ship's state: ann answers
/// every ask, bo keeps the drive, cy builds at crafts, di joins late on the
/// hull and breaks her watch for crafts.
fn officers(
  s : @core.State,
  now : Int64,
  start : Int64,
) -> Array[(String, @core.Intent)] {
  guard s.crossing() is Some(c) && c.arrived_at is None else { return [] }
  let out = []
  let on = (who : String) => c.hands.get(who).map(h => h.post)
  if c.ask is Some(post) && on("ann") != Some(post) {
    out.push(("ann", @core.Intent::Posted(post~)))
  }
  if on("bo") is None {
    out.push(("bo", Posted(post=Drive)))
    out.push(("bo", Watched(ticks=4L * @core.HOUR)))
  }
  if on("cy") is None {
    out.push(("cy", Posted(post=Craft)))
    out.push(("cy", Crafted(craft=Engineer)))
  }
  let since = now - start
  if since >= 2L * @core.HOUR && on("di") is None {
    out.push(("di", Posted(post=Hull)))
    out.push(("di", Watched(ticks=3L * @core.HOUR)))
  }
  if since >= 4L * @core.HOUR &&
    c.hands.get("di") is Some(h) &&
    h.watch is Some(_) {
    out.push(("di", Posted(post=Craft)))
  }
  out
}
