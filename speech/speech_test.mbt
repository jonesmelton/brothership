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

///|
fn tally() -> @core.Tally {
  {
    drive: 3 * 4 * 3600,
    hull: 2 * 4 * 3600,
    craft: 0,
    regard: 0,
    work: 0,
    watches_stood: 2,
    watches_broken: 1,
  }
}

///|
test "a promotion beats the arrival and is spoken inside the quiet window" {
  let story = [
    entry(5, T0 + 60, Began(phase=Arrived)),
    entry(6, T0 + 60, Promoted(crew="ann", rank=2, tally=tally())),
  ]
  debug_inspect(
    @speech.worth(story, quiet_until=0).map(e => e.seq),
    content="Some(6)",
  )
  debug_inspect(
    @speech.worth(story, quiet_until=T0 + @speech.QUIET).map(e => e.seq),
    content="Some(6)",
  )
  debug_inspect(
    @speech.worth(
      [entry(6, T0 + 60, Promoted(crew="ann", rank=2, tally=tally()))],
      quiet_until=T0 + @speech.QUIET,
    ).map(e => e.seq),
    content="Some(6)",
  )
}

///|
async test "a promotion prompt carries facts about the officer and no id" {
  let store = departed()
  defer store.close()
  let state = store.snapshot("tigress").unwrap().state
  let state = {
    ..state,
    ship: {
      ..state.ship,
      records: {
        "officer-9f3a": {
          regard: 130 * @core.REGARD_HOUR,
          works: 4,
          carry: 0,
          rank: Some(2),
        },
      },
    },
  }
  let promoted = entry(
    9,
    T0 + 900,
    Promoted(crew="officer-9f3a", rank=2, tally=tally()),
  )
  let call = speech().call(voice(), state, [promoted], promoted)
  assert_false(call.user.contains("officer-9f3a"))
  debug_inspect(
    call.user,
    content=(
      #|"# what just happened\n\nA hand was promoted to lieutenant.\n\n# the officer promoted\n\n- New rank: lieutenant.\n- Hours on the drive this crossing: 3.\n- Hours on the hull this crossing: 2.\n- Hours at crafts this crossing: 0.\n- Watches stood this crossing: 2.\n- Watches broken this crossing: 1.\n- Works finished in all: 4.\n- Hours of regard on record: 130.\n\nYou have no name or handle for them: speak of them by what they did.\n\n# where you are\n\nBurning toward the next port.\nArriving in about 18 hours, if the drive stays as set.\nHull at 100%.\nDrive at 35% of full burn, with none of the 5 hands it needs.\nNobody is on a post yet.\nThe ship asks for hands on the drive.\n\n# your crew this crossing\n\n- Nobody has taken a post yet.\n\n# earlier on this crossing\n\n- Nothing yet.\n\n# what you are asking for\n\nHands on the drive.\n"
    ),
  )
}

///|
test "a line that opens like an earlier one, or reuses most of its words, repeats" {
  let earlier = [
    "Hands to the hull, loves, the plating is thin.", "Steady burn now; the drive is singing for us all tonight.",
  ]
  debug_inspect(
    [
      "Hands to the hull, quickly!", "The drive is singing tonight for us all, steady now.",
      "Who will sit the night watch with me?",
    ].map(line => @speech.repeats(line, earlier)),
    content="[true, true, false]",
  )
}

///|
async test "the ship can pass, and says nothing" {
  let store = departed()
  defer store.close()
  let calls = Ref(0)
  let speaker = @speech.Speaker::new(
    "tigress",
    voice(),
    speech(),
    fake("PASS", 0, calls),
    from=0,
  )
  speaker.step(store, clock=() => T0 + 620)
  inspect(calls.val, content="1")
  inspect(spoken(store).length(), content="0")
}

///|
async test "the speaker waits while the mind decides, then hears its thoughts" {
  let store = departed()
  defer store.close()
  let calls = Ref(0)
  let busy = Ref(true)
  let seen : Ref[String] = Ref("")
  let backend = @llm.Backend::new("seen", c => {
    if c.model != "gate" {
      seen.val = c.user
    }
    fake("Eat first.", 0, calls).call(c)
  })
  let speaker = @speech.Speaker::new(
    "tigress",
    voice(),
    speech(),
    backend,
    from=0,
    busy=() => busy.val,
    thoughts=() => ["You asked for hands on the hull. You thought: mend first."],
  )
  speaker.step(store, clock=() => T0 + 620)
  inspect(calls.val, content="0")
  busy.val = false
  speaker.step(store, clock=() => T0 + 625)
  inspect(calls.val, content="2")
  assert_true(seen.val.contains("You thought: mend first."))
}
