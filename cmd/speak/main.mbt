// Flies one ship through a crossing in memory and prints each line it
// writes, as the server's speaker would. For hearing a ship's voice before
// it flies. Run from the repository root.
//
//   moon run cmd/speak -- [--replay] [ship]
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
  let id = args.iter().find_first(a => !a.has_prefix("--")).unwrap_or("tigress")
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
    model="meta:muse-spark-1.3",
    gate_model="meta:muse-spark-1.3",
  )
  let store = @store.Store::open(":memory:")
  defer store.close()
  store.commission(berth)
  let speaker = @speech.Speaker::new(id, voice, speech, backend, from=0)
  let mut now = START
  let mut shown = 0L
  // One crossing: until the ship docks once.
  while store.snapshot(id).unwrap().state.ship.crossings < 1L {
    store.advance(id, now~)
    speaker.step(store, clock=() => now)
    for e in store.story(id, after=shown).unwrap() {
      let hours = (e.at - START) / 3600L
      let minutes = (e.at - START) % 3600L / 60L
      let line = match e.happening {
        Spoke(line~, ..) => "  \{voice.epithet}: \{line}"
        h =>
          "\{hours}h\{minutes}m \{@words.told(h, you="", ship=voice.epithet)}"
      }
      println(line)
      shown = e.seq
    }
    now = berth.next_advance(store.snapshot(id).unwrap().state, now)
  }
}
