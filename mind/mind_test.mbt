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
    cruise="{% for c in courses %}{{ c.name }} {% endfor %}",
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
    cruise="{% for c in courses %}{{ c.name }} {% endfor %}",
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
  let c = @core.Crossing::new(
    p.next_plan(distance_ly=@ships.hop(0), coils=0),
    p.ship(seed=1),
  )
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

///|
test "a cruise is read by name from the reply" {
  debug_inspect(
    @mind.decode_cruise("{\"cruise\": \"steady\", \"thought\": \"Ease off.\"}"),
    content=(
      #|(800, "Ease off.")
    ),
  )
  inspect(@mind.decode_cruise("{\"cruise\": \"hard\"}").0, content="1000")
  let unreadable = try {
    ignore(@mind.decode_cruise("{\"cruise\": \"ludicrous\"}"))
    false
  } catch {
    _ => true
  }
  inspect(unreadable, content="true")
}

///|
/// A store with every berth commissioned and in port, `ship` minded.
async fn in_port(ship : String) -> @store.Store {
  let store = @store.Store::open(":memory:")
  for berth in @ships.fleet() {
    store.commission(berth)
  }
  store.mind(ship)
  store.advance(ship, now=T0)
  store
}

///|
async test "in port the mind chooses the cruise, once a stay" {
  let store = in_port("tigress")
  defer store.close()
  let calls = Ref(0)
  let mind = @mind.Mind::new(
    "tigress",
    @ships.fleet()[0].profile,
    voice(),
    prompts(),
    model="m",
    model("{\"cruise\": \"easy\", \"thought\": \"Slow.\"}", calls),
  )
  mind.step(store, clock=() => T0 + 10)
  mind.step(store, clock=() => T0 + 20)
  inspect(calls.val, content="1")
  inspect(store.snapshot("tigress").unwrap().state.ship.cruise, content="600")
  store.advance("tigress", now=T0 + 600)
  let s = store.snapshot("tigress").unwrap().state
  let p = @ships.fleet()[0].profile
  let distance_ly = @ships.origin(s.ship).distance_to(
    @ships.bound_for(s).unwrap(),
  )
  assert_eq(
    s.crossing().unwrap().plan,
    p.next_plan(distance_ly~, coils=0, cruise=600),
  )
}

///|
test "the next world is read by name from the reply, among the choices" {
  let ship = @ships.profiles()[1].ship(seed=1)
  let course = (reply : String) => @mind.decode_course(reply, ship).name
  inspect(course("{\"course\": \"Oaxaca\"}"), content="Oaxaca")
  inspect(
    course("{\"course\": \" three tyrants \"}"),
    content="The Three Tyrants",
  )
  for
    reply in [
      "{\"course\": \"Kerala\"}", "{\"course\": \"Earth\"}", "{\"cruise\": \"hard\"}",
    ] {
    let unreadable = try {
      ignore(@mind.decode_course(reply, ship))
      false
    } catch {
      _ => true
    }
    assert_true(unreadable, msg=reply)
  }
}

///|
async test "in port the mind chooses the next world, which the ship flies to" {
  let store = in_port("tigress")
  defer store.close()
  let calls = Ref(0)
  let mind = @mind.Mind::new(
    "tigress",
    @ships.fleet()[0].profile,
    voice(),
    prompts(),
    model="m",
    model(
      "{\"course\": \"Oaxaca\", \"cruise\": \"hard\", \"ask\": \"drive\", \"thought\": \"South.\"}",
      calls,
    ),
  )
  mind.step(store, clock=() => T0 + 10)
  let s = store.snapshot("tigress").unwrap().state
  debug_inspect(
    s.ship.bound,
    content=(
      #|Some("Oaxaca")
    ),
  )
  let story = store.story("tigress", after=0).unwrap()
  inspect(
    story.iter().any(e => e.happening is Bound(world="Oaxaca")),
    content="true",
  )
  store.advance("tigress", now=T0 + 600)
  let s = store.snapshot("tigress").unwrap().state
  let p = @ships.fleet()[0].profile
  let kerala = @ships.world_named("Kerala").unwrap()
  let oaxaca = @ships.world_named("Oaxaca").unwrap()
  assert_eq(
    s.crossing().unwrap().plan,
    p.next_plan(distance_ly=kerala.distance_to(oaxaca), coils=0),
  )
}

///|
async test "a world the ship may not choose falls back to its temperament" {
  let store = in_port("tigress")
  defer store.close()
  let calls = Ref(0)
  let p = @ships.fleet()[0].profile
  let mind = @mind.Mind::new(
    "tigress",
    p,
    voice(),
    prompts(),
    model="m",
    model("{\"course\": \"Kerala\", \"cruise\": \"easy\"}", calls),
  )
  mind.step(store, clock=() => T0 + 10)
  let s = store.snapshot("tigress").unwrap().state
  assert_eq(s.ship.bound, Some(p.temperament.course(s.ship).name))
  inspect(s.ship.cruise, content="600")
}

///|
async test "the cruise prompt offers each world with its visits and the fleet" {
  let store = in_port("tigress")
  defer store.close()
  store.advance("flea", now=T0)
  let p = @ships.fleet()[0].profile
  let state = store.snapshot("tigress").unwrap().state
  let flea = store.snapshot("flea").unwrap().state
  let flea = { ..flea, ship: { ..flea.ship, bound: Some("Occitan"), }, }
  let story = store.story("tigress", after=0).unwrap()
  let prompts = @mind.Prompts::new(
    system="",
    turn="",
    muster="",
    cruise=(
      #|{% for c in courses %}{{ c.name }}, {{ c.star }}, {{ c.distance }}. {{ c.visits }} {{ c.leaves }}
      #|{% for f in c.fleet %}  {{ f }}
      #|{% endfor %}{% for k in c.cruises %}  {{ k.name }}: {{ k.hours }}
      #|{% endfor %}{% endfor %}
    ),
    setting="",
  )
  let call = prompts.cruise(
    voice(),
    values=p.values,
    model="m",
    profile=p,
    state,
    story,
    thoughts=[],
    fleet=[flea],
  )
  inspect(
    call.user,
    content=(
      #|Tigray, 70 Ophiuchi, 24.2 light-years. You have never docked here. With the crew posted as they are, you would leave in about 10 minutes.
      #|  hard: 13 to 22 hours
      #|  steady: 15 to 24 hours
      #|  easy: 19 to 27 hours
      #|Oaxaca, δ Pavonis, 20.0 light-years. You have never docked here. With the crew posted as they are, you would leave in about 10 minutes.
      #|  hard: 12 to 21 hours
      #|  steady: 13 to 22 hours
      #|  easy: 16 to 25 hours
      #|Occitan, 61 Cygni, 15.7 light-years. You have never docked here. With the crew posted as they are, you would leave in about 10 minutes.
      #|  The Flea on the Drum is in port at Kerala, and has chosen to go there next.
      #|  hard: 10 to 19 hours
      #|  steady: 11 to 20 hours
      #|  easy: 14 to 22 hours
      #|The Three Tyrants, Gliese 667, 29.6 light-years. You have never docked here. With the crew posted as they are, you would leave in about 10 minutes.
      #|  hard: 15 to 24 hours
      #|  steady: 18 to 27 hours
      #|  easy: 22 to 31 hours
      #|
    ),
  )
}

///|
async test "a failed cruise call falls back to the temperament" {
  let store = in_port("flea")
  defer store.close()
  let calls = Ref(0)
  let p = @ships.fleet()[2].profile
  let mind = @mind.Mind::new(
    "flea",
    p,
    voice(),
    prompts(),
    model="m",
    model("", calls),
  )
  mind.step(store, clock=() => T0 + 10)
  let s = store.snapshot("flea").unwrap().state
  let distance_ly = @ships.origin(s.ship).distance_to(
    @ships.bound_for(s).unwrap(),
  )
  assert_eq(s.ship.bound, Some(p.temperament.course(s.ship).name))
  assert_eq(s.ship.cruise, p.temperament.cruise(s.ship, distance_ly~))
}

///|
async test "the authored cruise prompt renders, after a crossing" {
  let prompts = @mind.Prompts::load(content="../content") catch {
    _ => @mind.Prompts::load(content="content")
  }
  let store = in_port("tigress")
  defer store.close()
  let p = @ships.fleet()[0].profile
  // Left alone to its second port, so it has come from somewhere.
  let mut now = T0
  while store.snapshot("tigress").unwrap().state.ship.crossings < 1L {
    now += 600L
    store.advance("tigress", now~)
  }
  let state = store.snapshot("tigress").unwrap().state
  let story = store.story("tigress", after=0).unwrap()
  let call = prompts.cruise(
    voice(),
    values=p.values,
    model="m",
    profile=p,
    state,
    story,
    thoughts=["You liked the last port."],
    fleet=[],
  )
  let user = call.user
  assert_true(
    user.contains(
      "You came here from Kerala, and you do not fly straight back.",
    ),
    msg=user,
  )
  assert_true(user.contains("## Oaxaca, by the star δ Pavonis\n\n"), msg=user)
  assert_true(
    user.contains(
      "You have just flown a short crossing, under eighteen light-years",
    ),
    msg=user,
  )
  assert_true(
    user.contains("`course`: one of \"Oaxaca\", \"The Three Tyrants\"."),
    msg=user,
  )
  assert_false(user.contains("## Kerala"), msg=user)
}

///|
async test "a world chosen earlier in the port stay stands" {
  let store = in_port("tigress")
  defer store.close()
  let calls = Ref(0)
  let reply = "{\"course\": \"Oaxaca\", \"cruise\": \"hard\"}"
  let first = @mind.Mind::new(
    "tigress",
    @ships.fleet()[0].profile,
    voice(),
    prompts(),
    model="m",
    model(reply, calls),
  )
  first.step(store, clock=() => T0 + 10)
  // A restart: a new mind, which weighs the port stay again.
  let again = @mind.Mind::new(
    "tigress",
    @ships.fleet()[0].profile,
    voice(),
    prompts(),
    model="m",
    model("{\"course\": \"Tigray\", \"cruise\": \"easy\"}", calls),
  )
  again.step(store, clock=() => T0 + 20)
  inspect(calls.val, content="2")
  let s = store.snapshot("tigress").unwrap().state
  debug_inspect(
    (s.ship.bound, s.ship.cruise),
    content=(
      #|(Some("Oaxaca"), 600)
    ),
  )
  let bound = store
    .story("tigress", after=0)
    .unwrap()
    .filter(e => e.happening is Bound(_))
  inspect(bound.length(), content="1")
}

///|
/// A model that replies with each of `replies` in turn, then the last.
fn scripted(replies : Array[String]) -> @llm.Backend {
  let next = Ref(0)
  @llm.Backend::new("fake", fn(c) {
    let text = replies[next.val.min(replies.length() - 1)]
    next.val += 1
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
async test "the nearest world for a second port running gives way to the temperament, and its reason is dropped" {
  let store = in_port("scorpion")
  defer store.close()
  let p = @ships.fleet()[1].profile
  let mind = @mind.Mind::new(
    "scorpion",
    p,
    voice(),
    prompts(),
    model="m",
    scripted([
      "{\"course\": \"Occitan\", \"cruise\": \"hard\", \"thought\": \"Close by.\"}",
      "{\"course\": \"Oaxaca\", \"cruise\": \"easy\", \"thought\": \"Oaxaca again, close by.\"}",
    ]),
  )
  mind.step(store, clock=() => T0 + 10)
  store.advance("scorpion", now=T0 + 600)
  let docked = T0 + 400_000
  store.advance("scorpion", now=docked)
  let s = store.snapshot("scorpion").unwrap().state
  assert_true(s.leg is InPort(_))
  assert_eq(@ships.origin(s.ship).name, "Occitan")
  mind.step(store, clock=() => docked + 1)
  let s = store.snapshot("scorpion").unwrap().state
  debug_inspect(
    (s.ship.bound, s.ship.cruise),
    content=(
      #|(Some("The Three Tyrants"), 600)
    ),
  )
  assert_false(mind.thoughts().last().unwrap().contains("Oaxaca"))
}

///|
async test "the cruise prompt gives the ship its leaning" {
  let store = in_port("scorpion")
  defer store.close()
  let p = @ships.fleet()[1].profile
  let state = store.snapshot("scorpion").unwrap().state
  let prompts = @mind.Prompts::new(
    system="",
    turn="",
    muster="",
    cruise="{{ leaning }}",
    setting="",
  )
  let call = prompts.cruise(
    voice(),
    values=p.values,
    model="m",
    profile=p,
    state,
    store.story("scorpion", after=0).unwrap(),
    thoughts=[],
    fleet=[],
  )
  assert_true(call.user.contains("farthest"), msg=call.user)
}
