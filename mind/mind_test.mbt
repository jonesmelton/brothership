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
