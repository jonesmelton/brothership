///|
const T0 : Int64 = 1_800_000_000L

///|
fn entry(seq : Int64, at : Int64, h : @core.Happening) -> @core.Entry {
  { seq, at, happening: h, }
}

///|
test "the most pressing happening earns a line, and crew moves none" {
  let story = [
    entry(4, T0, Took(crew="bo", post=Hull)),
    entry(5, T0, Met(hazard=Flare)),
    entry(6, T0, Opened(hazard=Breach)),
    entry(7, T0, Began(phase=Coast)),
  ]
  debug_inspect(
    @speech.worth(story, quiet_until=0).map(e => e.seq),
    content="Some(6)",
  )
  debug_inspect(
    @speech.worth(story[:2].to_owned(), quiet_until=0).map(e => e.seq),
    content="Some(5)",
  )
  debug_inspect(
    @speech.worth([entry(4, T0, Took(crew="bo", post=Hull))], quiet_until=0),
    content="None",
  )
}

///|
test "soon after a line, only departures, arrivals and new demands are spoken" {
  let later = T0 + 60
  let quiet = [
    entry(5, later, Met(hazard=Flare)),
    entry(7, later, Began(phase=Coast)),
  ]
  debug_inspect(@speech.worth(quiet, quiet_until=T0 + 900), content="None")
  debug_inspect(
    @speech.worth(
      [..quiet, entry(8, later, Began(phase=Arrived))],
      quiet_until=T0 + 900,
    ).map(e => e.seq),
    content="Some(8)",
  )
}

///|
test "a reply is tidied into one plain line, or refused" {
  debug_inspect(
    [
      "  \"Hands to the hull, loves!\"\n",
      "Hands to the hull.\n\nAnd quickly.",
      "**Hands** to the hull.",
      "",
      "word ".repeat(70),
    ].map(@speech.tidy),
    content=(
      #|[
      #|  Some("Hands to the hull, loves!"),
      #|  Some("Hands to the hull. And quickly."),
      #|  None,
      #|  None,
      #|  None,
      #|]
    ),
  )
}

///|
/// A model that writes `line` and a gate that says `verdict`, counting calls.
fn fake(line : String, verdict : Int32, calls : Ref[Int32]) -> @llm.Backend {
  @llm.Backend::new("fake", fn(c) {
    calls.val += 1
    let text = if c.model == "gate" {
      "{\"violation\": \{verdict}, \"evidence\": \"\"}"
    } else {
      line
    }
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
async fn speech() -> @speech.Speech {
  let read = async fn(path : String) { @fs.read_file(path).text() }
  @speech.Speech::new(
    system=read("content/speech/system.md"),
    user=read("content/speech/user.md"),
    setting=read("content/cast/prompts/setting.md"),
    model="writer",
    gate=@llm_gate.Gate::new(model="gate", policy="the policy"),
  )
}

///|
fn voice() -> @speech.Voice {
  {
    epithet: "The Tigress",
    captain: "I keep a warm table.",
    voice: "Eat first.",
  }
}

///|
/// A store with the Tigress just departed.
async fn departed() -> @store.Store {
  let store = @store.Store::open(":memory:")
  store.commission(@ships.fleet()[0])
  store.advance("tigress", now=T0)
  store.advance("tigress", now=T0 + 600)
  store
}

///|
fn spoken(store : @store.Store) -> Array[@core.Happening] {
  store
  .story("tigress", after=0)
  .unwrap()
  .filter(e => e.happening is Spoke(_))
  .map(e => e.happening)
}

///|
async test "the ship answers its departure with a gated line" {
  let store = departed()
  defer store.close()
  let calls = Ref(0)
  let speaker = @speech.Speaker::new(
    "tigress",
    voice(),
    speech(),
    fake("Eat first, loves; the drive wants hands.", 0, calls),
    from=0,
  )
  speaker.step(store, clock=() => T0 + 620)
  inspect(calls.val, content="2")
  let departed_at = store.story("tigress", after=0).unwrap()[0].seq
  assert_eq(spoken(store), [
    Spoke(line="Eat first, loves; the drive wants hands.", about=departed_at),
  ])
  inspect(speaker.speaking(), content="false")
  // Nothing new: no call.
  speaker.step(store, clock=() => T0 + 640)
  inspect(calls.val, content="2")
}

///|
async test "a blocked or failed line leaves nothing" {
  let store = departed()
  defer store.close()
  let calls = Ref(0)
  let blocked = @speech.Speaker::new(
    "tigress",
    voice(),
    speech(),
    fake("Something unkind.", 1, calls),
    from=0,
  )
  blocked.step(store, clock=() => T0 + 620)
  inspect(calls.val, content="2")
  let failing = @speech.Speaker::new(
    "tigress",
    voice(),
    speech(),
    @llm.Backend::new("down", _ => fail("no route")),
    from=0,
  )
  failing.step(store, clock=() => T0 + 620)
  inspect(spoken(store).length(), content="0")
}

///|
async test "the prompt carries the faces, the readout and what happened" {
  let store = departed()
  defer store.close()
  let story = store.story("tigress", after=0).unwrap()
  let call = speech().call(
    voice(),
    store.snapshot("tigress").unwrap().state,
    story,
    story[0],
  )
  assert_true(call.system[0].contains("You are The Tigress"))
  assert_true(call.system[0].contains("I keep a warm table."))
  assert_true(call.user.contains("The ship left port."))
  assert_true(call.user.contains("Burning toward the next port."))
  assert_true(call.user.contains("Hands on the drive."))
}
