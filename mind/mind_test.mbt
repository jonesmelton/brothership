///|
const T0 : Int64 = 1_800_000_000L

///|
fn voice() -> @speech.Voice {
  { epithet: "The Tigress", captain: "I am the Tigress.", voice: "", }
}

///|
fn prompts() -> @mind.Prompts {
  @mind.Prompts::new(
    system="{{ epithet }}: {{ captain }}",
    turn="{{ ask }} {{ refit }}{% for r in refits %} {{ r.name }}{% endfor %}",
    muster="{% for line in roster %}{{ line }}\n{% endfor %}",
    setting="",
  )
}

///|
/// A model that replies `text`, or fails if `text` is empty, counting calls.
fn model(text : String, calls : Ref[Int32]) -> @llm.Backend {
  @llm.Backend::new("fake", fn(c) raise {
    calls.val += 1
    guard text != "" else { fail("no route") }
    {
      model: c.model,
      text,
      reasoning: None,
      finish: Some("stop"),
      usage: @llm.Usage::zero(),
      raw: Json::null(),
    }
  })
}

///|
async fn underway() -> @store.Store {
  let store = @store.Store::open(":memory:")
  for berth in @ships.fleet() {
    store.commission(berth)
  }
  store.mind("tigress")
  store.advance("tigress", now=T0)
  store.advance("tigress", now=T0 + 600)
  store
}

///|
/// Prompts whose muster text is marked, so a test can count cycles.
fn cycle_prompts() -> @mind.Prompts {
  @mind.Prompts::new(
    system="{{ epithet }}",
    turn="{{ ask }} {{ refit }}",
    muster="CYCLE {{ arrived }}{% for line in roster %} {{ line }}{% endfor %}",
    setting="",
  )
}

///|
/// A model that replies `text`, or fails if it is empty, counting all calls
/// and the cycles among them.
fn cycle_model(
  text : String,
  calls : Ref[Int32],
  cycles : Ref[Int32],
) -> @llm.Backend {
  @llm.Backend::new("fake", fn(c) raise {
    calls.val += 1
    if c.user.find("CYCLE") is Some(_) {
      cycles.val += 1
    }
    guard text != "" else { fail("no route") }
    {
      model: c.model,
      text,
      reasoning: None,
      finish: Some("stop"),
      usage: @llm.Usage::zero(),
      raw: Json::null(),
    }
  })
}

///|
/// A minded Tigress underway with four officers who have served six hours.
async fn four_served() -> (@store.Store, Int64) {
  let store = underway()
  for i, crew in ["ann", "bo", "cy", "di"] {
    ignore(
      store.propose(
        "tigress",
        { id: i.to_int64() + 1L, crew, intent: Posted(post=Drive), },
        now=T0 + 601,
      ),
    )
  }
  let mut now = T0 + 601
  for _ in 0..<10_000 {
    let s = store.snapshot("tigress").unwrap().state
    guard @ships.arrived_at(s) is None else { break }
    guard s.crossing().unwrap().served("ann") < @ships.ENSIGN_SERVICE else {
      break
    }
    now += 120L
    store.advance("tigress", now~)
  }
  (store, now)
}

///|
test "a turn is read from the reply's object, tolerating noise" {
  let p = @ships.profiles()[1]
  let c = @core.Crossing::new(p.next_plan(legs=0, coils=0), p.ship(seed=1))
  debug_inspect(
    @mind.decode_turn(
      "Sure: {\"ask\": \"hull\", \"refit\": \"baffles\", \"thought\": \" Mend first. \"}",
      c,
    ),
    content=(
      #|{
      #|  acts: [Ask(Some(Hull)), Refit(Some(Baffles))],
      #|  thought: "Mend first.",
      #|}
    ),
  )
  debug_inspect(
    @mind.decode_turn("{\"ask\": \"nothing\", \"refit\": \"warp\"}", c),
    content=(
      #|{ acts: [Ask(None)], thought: "" }
    ),
  )
  let unreadable = try {
    ignore(@mind.decode_turn("{\"refit\": \"coils\"}", c))
    false
  } catch {
    _ => true
  }
  inspect(unreadable, content="true")
}

///|
test "promotions are read by handle" {
  let names : Map[String, String] = { "officer-1": "A", "officer-2": "B" }
  debug_inspect(
    @mind.decode_muster(
      "{\"promote\": [\"Hand B\", \"Z\", \"A\"], \"thought\": \"B first.\"}", names,
    ),
    content=(
      #|(["officer-2", "officer-1"], "B first.")
    ),
  )
}

///|
async test "the mind's turn is the model's when it answers" {
  let store = underway()
  defer store.close()
  let calls = Ref(0)
  let mind = @mind.Mind::new(
    "tigress",
    @ships.fleet()[0].profile,
    voice(),
    prompts(),
    model="m",
    model(
      "{\"ask\": \"crafts\", \"refit\": \"coils\", \"thought\": \"Make things.\"}",
      calls,
    ),
  )
  mind.step(store, clock=() => T0 + 610)
  let c = store.snapshot("tigress").unwrap().state.crossing().unwrap()
  debug_inspect((c.ask, c.fit.refit), content="(Some(Craft), Some(Coils))")
  mind.step(store, clock=() => T0 + 615)
  inspect(calls.val, content="1")
  debug_inspect(
    mind.thoughts(),
    content=(
      #|["You asked for hands on crafts. You set the engineers to coils. You thought: Make things."]
    ),
  )
}

///|
async test "a failed call falls back to the temperament" {
  let store = underway()
  defer store.close()
  let calls = Ref(0)
  let mind = @mind.Mind::new(
    "tigress",
    @ships.fleet()[0].profile,
    voice(),
    prompts(),
    model="m",
    model("", calls),
  )
  mind.step(store, clock=() => T0 + 610)
  let c = store.snapshot("tigress").unwrap().state.crossing().unwrap()
  debug_inspect((c.ask, c.fit.refit), content="(Some(Drive), Some(Plating))")
  mind.step(store, clock=() => T0 + 615)
  inspect(calls.val, content="1")
}

///|
async test "at arrival the mind promotes whom the model names, then docks" {
  let store = underway()
  defer store.close()
  for i, crew in ["ann", "bo"] {
    ignore(
      store.propose(
        "tigress",
        { id: i.to_int64(), crew, intent: Posted(post=Drive), },
        now=T0 + 601,
      ),
    )
  }
  let mut now = T0 + 601
  for _ in 0..<10_000 {
    guard @ships.arrived_at(store.snapshot("tigress").unwrap().state) is None else {
      break
    }
    now += 120L
    store.advance("tigress", now~)
  }
  let calls = Ref(0)
  let mind = @mind.Mind::new(
    "tigress",
    @ships.fleet()[0].profile,
    voice(),
    prompts(),
    model="m",
    model("{\"promote\": [\"B\"], \"thought\": \"Bo stayed.\"}", calls),
  )
  mind.step(store, clock=() => now + 5)
  let s = store.snapshot("tigress").unwrap().state
  inspect(s.leg is InPort(..), content="true")
  debug_inspect((s.ship.rank("ann"), s.ship.rank("bo")), content="(0, 1)")
}

///|
async test "a bottom-heavy ship promotes underway at most every half hour" {
  let (store, now) = four_served()
  defer store.close()
  let calls = Ref(0)
  let cycles = Ref(0)
  let mind = @mind.Mind::new(
    "tigress",
    @ships.fleet()[0].profile,
    voice(),
    cycle_prompts(),
    model="m",
    cycle_model(
      "{\"ask\": \"drive\", \"promote\": [\"A\"], \"thought\": \"first\"}", calls,
      cycles,
    ),
  )
  let at = now
  // The turn comes first, and is not a cycle.
  mind.step(store, clock=() => at)
  inspect(cycles.val, content="0")
  mind.step(store, clock=() => at)
  inspect(cycles.val, content="1")
  debug_inspect(
    store.snapshot("tigress").unwrap().state.crossing().unwrap().hands
    .get("ann")
    .unwrap().rank,
    content="1",
  )
  // Within the gap, no further cycle call.
  mind.step(store, clock=() => at)
  inspect(cycles.val, content="1")
}

///|
async test "a failed cycle falls back to the longest-serving ensign" {
  let (store, now) = four_served()
  defer store.close()
  let calls = Ref(0)
  let mind = @mind.Mind::new(
    "tigress",
    @ships.fleet()[0].profile,
    voice(),
    cycle_prompts(),
    model="m",
    model("", calls),
  )
  mind.step(store, clock=() => now)
  mind.step(store, clock=() => now)
  // Service is tied, and String order is by length first, so bo leads.
  let hands = store.snapshot("tigress").unwrap().state.crossing().unwrap().hands
  debug_inspect(
    ["ann", "bo", "cy", "di"].map(id => hands.get(id).unwrap().rank),
    content="[0, 1, 0, 0]",
  )
}
