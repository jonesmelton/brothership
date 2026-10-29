// Puts every ship's character into the same game state and prints what
// each chooses and says, so prompts and models can be compared on one
// moment. Run from the repository root.
//
//   moon run cmd/audition -- [--replay] [--mind M] [--writer M] [--gate M]
//     [--samples N] [scenario ...]
//
// Scenarios: departure, demand, coast, ensigns, arrival (default: all). Each is
// flown by the Tigress with four scripted officers; only the character
// changes. Replies are cached in .cache/llm, so a rerun is free.

///|
const START : Int64 = 1_800_000_000L

///|
const SHIP : String = "tigress"

///|
/// What the four officers do at `now`, given the ship's state: ann answers
/// every ask, bo keeps the drive, cy builds at crafts, di joins late on the
/// hull and breaks her watch for crafts.
fn crew_turn(
  s : @core.State,
  now : Int64,
  start : Int64,
) -> Array[(String, @core.Intent)] {
  guard s.crossing() is Some(c) else { return [] }
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

///|
/// A store with the Tigress flown, with its four officers, until `stop`
/// holds for its state and story. The ship is minded once `stop` is near,
/// so an arrival waits to be mustered.
async fn fly(stop : (@core.State, Array[@core.Entry]) -> Bool) -> @store.Store {
  let store = @store.Store::open(":memory:")
  let berth = @ships.fleet()[0]
  store.commission(berth)
  store.mind(SHIP)
  store.advance(SHIP, now=START)
  let mut now = START
  let mut id = 0L
  let mut departed : Int64? = None
  // Steps shorter than MIND_WAIT, so an arrival is still waiting.
  for _ in 0..<20_000 {
    let s = store.snapshot(SHIP).unwrap().state
    let story = store.story(SHIP, after=0).unwrap()
    if stop(s, story) {
      break
    }
    match s.leg {
      Underway(crossing=c, spoke~) if c.arrived_at is None => {
        if departed is None {
          departed = Some(now)
        }
        if spoke != Some(c.moment()) {
          let acts = berth.profile.temperament.turn(c, spoke)
          ignore(store.decide(SHIP, acts, moment=c.moment(), now~))
        }
        let s = store.snapshot(SHIP).unwrap().state
        for pair in crew_turn(s, now, departed.unwrap()) {
          id += 1L
          ignore(
            store.propose(SHIP, { id, crew: pair.0, intent: pair.1, }, now~),
          )
        }
      }
      _ => ()
    }
    now += 120L
    store.advance(SHIP, now~)
  }
  store
}

///|
/// A scenario: its name, what it shows, and where the flight stops.
priv struct Scenario {
  name : String
  about : String
  stop : (@core.State, Array[@core.Entry]) -> Bool
}

///|
fn has(story : Array[@core.Entry], f : (@core.Happening) -> Bool) -> Bool {
  story.iter().any(e => f(e.happening))
}

///|
let scenarios : Array[Scenario] = [
  {
    name: "departure",
    about: "an hour out of port, crew settling",
    stop: (s, _) => s.crossing() is Some(c) && c.t >= @core.HOUR,
  },
  {
    name: "demand",
    about: "the first demand of the crossing has just opened",
    stop: (_, story) => has(story, h => h is Opened(_)),
  },
  {
    name: "coast",
    about: "the coast has begun; the drive does nothing for hours",
    stop: (_, story) => has(story, h => h is Began(phase=Coast)),
  },
  {
    name: "ensigns",
    about: "six hours out, every officer still an ensign; the ship may promote underway",
    stop: (s, _) => {
      s.crossing() is Some(c) && c.served("ann") >= @ships.ENSIGN_SERVICE
    },
  },
  {
    name: "arrival",
    about: "arrived; the ship chooses whom to promote before docking",
    stop: (s, _) => @ships.arrived_at(s) is Some(_),
  },
]

///|
fn flag(args : Array[String], name : String) -> String? {
  for i, a in args {
    if a == name && i + 1 < args.length() {
      return Some(args[i + 1])
    }
  }
  None
}

///|
fn tally(xs : Array[String]) -> String {
  let counts : Map[String, Int32] = Map([])
  for x in xs {
    counts[x] = counts.get(x).unwrap_or(0) + 1
  }
  counts.iter().map(p => "\{p.0} ×\{p.1}").collect().join(", ")
}

///|
async fn main {
  let args = @env.args()[1:].to_owned()
  let mode : @cache.Mode = if args.contains("--replay") { Replay } else { Live }
  let mind_model = flag(args, "--mind").unwrap_or(
    "meta:muse-spark-1.3-contributor",
  )
  let writer = flag(args, "--writer").unwrap_or(mind_model)
  let gate_model = flag(args, "--gate").unwrap_or(
    "meta:muse-spark-1.3-contributor",
  )
  let samples = match flag(args, "--samples") {
    Some(n) => @string.parse_int(n)
    None => 3
  }
  let values = ["--mind", "--writer", "--gate", "--samples"]
  let named = args.filter(a => {
    !a.has_prefix("--") && !values.iter().any(v => flag(args, v) == Some(a))
  })
  let chosen = if named.is_empty() {
    scenarios
  } else {
    scenarios.filter(s => named.contains(s.name))
  }
  let key = match (mode, @speech.meta_key()) {
    (Replay, _) => ""
    (Live, Some(key)) => key
    (Live, None) =>
      fail("set MODEL_API_KEY or write ~/.config/brothership/meta-api.key")
  }
  let spent = Ref(0.0)
  let inner = @cache.cached(@speech.meta_backend(key), dir=".cache/llm", mode~)
  let backend = @llm.Backend::new("counted", c => {
    let r = inner.call(c)
    spent.val += r.usage.cost_usd
    r
  })
  let prompts = @mind.Prompts::load(content="content")
  let speech = @speech.Speech::load(
    content="content",
    model=writer,
    gate_model~,
  )
  let voices = []
  for berth in @ships.fleet() {
    guard berth.profile.title is Some(title) &&
      @speech.Voice::load(content="content", title) is Some(voice) else {
      continue
    }
    voices.push((voice, berth.profile.values))
  }
  println(
    "# audition: mind \{mind_model}, writer \{writer}, \{samples} samples",
  )
  for sc in chosen {
    let store = fly(sc.stop)
    let snapshot = store.snapshot(SHIP).unwrap()
    let state = snapshot.state
    let story = store.story(SHIP, after=0).unwrap()
    let c = state.crossing().unwrap()
    println("\n## \{sc.name}: \{sc.about}\n")
    for line in @words.where_sentences(state) {
      println("    \{line}")
    }
    for line in @speech.roster(state, story) {
      println("    - \{line}")
    }
    let about = story
      .iter()
      .filter(e => @speech.worth([e], quiet_until=0) is Some(_))
      .last()
      .unwrap_or(story.last().unwrap())
    let arrival = @ships.arrived_at(state) is Some(_)
    let cycle = !arrival && @ships.bottom_heavy(c, officer=_ => true)
    let names = @speech.handles(c)
    for pair in voices {
      let (voice, values) = pair
      let mut first : @ships.Act? = None
      println("\n### \{voice.epithet}\n")
      let picks = []
      let thoughts = []
      for sample in 1..<=samples {
        try {
          if arrival || cycle {
            let call = {
              ..prompts.muster(
                voice,
                values~,
                model=mind_model,
                state,
                story,
                thoughts=[],
                arrived=arrival,
              ),
              sample,
            }
            let (crew, why) = @mind.decode_muster(
              backend.call(call).text,
              names,
            )
            let handles = crew.map(id => names.get(id).unwrap_or("?"))
            picks.push(
              if handles.is_empty() {
                "nobody"
              } else {
                handles.join("+")
              },
            )
            thoughts.push(why)
          } else {
            let call = {
              ..prompts.turn(voice, values~, model=mind_model, state, story, thoughts=[]),
              sample,
            }
            let choice = @mind.decode_turn(backend.call(call).text, c)
            if first is None {
              first = choice.acts.iter().find_first(a => a is Ask(_))
            }
            let ask = choice.acts
              .filter_map(a => if a is Ask(p) { Some(p) } else { None })
              .map(p => p.map(@words.post_name).unwrap_or("nothing"))
            let refit = choice.acts
              .filter_map(a => if a is Refit(r) { Some(r) } else { None })
              .map(r => r.map(@words.refit_name).unwrap_or("none"))
            picks.push(
              "\{ask.join("")}\{if refit.is_empty() { "" } else { " / " + refit.join("") }}",
            )
            thoughts.push(choice.thought)
          }
        } catch {
          err => picks.push("failed (\{err})")
        }
      }
      println("- chose: \{tally(picks)}")
      for t in thoughts {
        println("  - \{t}")
      }
      // The line follows the first sample's ask, as on the server.
      let heard = match (first, state.leg) {
        (Some(Ask(ask)), Underway(crossing~, spoke~)) =>
          { ..state, leg: Underway(crossing={ ..crossing, ask, }, spoke~), }
        _ => state
      }
      let line = try {
        let said = speech.line(
          backend,
          voice,
          heard,
          story,
          about,
          thoughts=thoughts[:1].to_owned(),
        )
        said.text()
      } catch {
        err => "(\{err})"
      }
      println(
        "- says, on \"\{@words.told(about.happening, you="", ship=voice.epithet)}\": \{line}",
      )
    }
    store.close()
  }
  println("\nspent about $\{spent.val}")
}
