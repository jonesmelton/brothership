// The ship speaks: which happening earns a line, the prompt that asks a
// model for it, and the speaker that writes it, gated, into the log.
// See docs/plans/story-and-speech.md and "model latency" in
// docs/architecture.md.

///|
/// A ship's approved faces, from `content/cast/ships/<pennant>/`.
pub(all) struct Voice {
  epithet : String
  captain : String
  voice : String
}

///|
/// The prompts and models every ship's lines are written with.
pub struct Speech {
  priv prompts : @prompt.Prompts
  priv setting : String
  priv model : String
  priv gate : @llm_gate.Gate
}

///|
/// `system` and `user` are the templates in `content/speech/`; `setting` is
/// `content/cast/prompts/setting.md`.
pub fn Speech::new(
  system~ : String,
  user~ : String,
  setting~ : String,
  model~ : String,
  gate~ : @llm_gate.Gate,
) -> Speech {
  {
    prompts: @prompt.Prompts::new(Map([("system", system), ("user", user)])),
    setting,
    model,
    gate,
  }
}

///|
/// Longest line kept, in words. The prompt asks for 40.
const MAX_WORDS : Int32 = 60

///|
/// How long after a line the ship keeps quiet about anything but a
/// departure, an arrival or a new demand, in seconds.
pub const QUIET : Int64 = 900

///|
/// How much a happening deserves a line; `None` for never.
fn weight(h : @core.Happening) -> Int32? {
  match h {
    Opened(_) => Some(7)
    Missed(_) | Promoted(..) => Some(6)
    Began(phase=Arrived) | Departed => Some(5)
    Began(_) => Some(4)
    Met(_) => Some(3)
    Landed(..) => Some(2)
    Docked(_)
    | Asked(_)
    | Took(..)
    | Left(_)
    | Stood(_)
    | Finished(_)
    | Spoke(..) => None
  }
}

///|
/// Spoken even within `QUIET` of the last line. A promotion lands with the
/// arrival, which is urgent anyway, and must not be lost to the quiet.
fn urgent(h : @core.Happening) -> Bool {
  h is (Opened(_) | Departed | Began(phase=Arrived) | Promoted(..))
}

///|
/// The happening in `story` most deserving of a line, the latest of equals.
/// Before `quiet_until`, in Unix seconds, only urgent ones count.
pub fn worth(story : Array[@core.Entry], quiet_until~ : Int64) -> @core.Entry? {
  let mut best : (@core.Entry, Int32)? = None
  for e in story {
    guard weight(e.happening) is Some(w) else { continue }
    guard e.at >= quiet_until || urgent(e.happening) else { continue }
    match best {
      Some((_, b)) if b > w => ()
      _ => best = Some((e, w))
    }
  }
  best.map(b => b.0)
}

///|
/// The reply as one plain line: whitespace collapsed, surrounding quotes
/// dropped. `None` if it is empty, longer than `MAX_WORDS`, or formatted.
pub fn tidy(reply : String) -> String? {
  let words = []
  let word = StringBuilder()
  for ch in reply {
    if ch.is_whitespace() {
      if word.to_string() != "" {
        words.push(word.to_string())
        word.reset()
      }
    } else {
      word.write_char(ch)
    }
  }
  if word.to_string() != "" {
    words.push(word.to_string())
  }
  guard words.length() > 0 && words.length() <= MAX_WORDS else { None }
  let line = words.join(" ")
  let quotes = ['"', '\'', '\u{201c}', '\u{201d}']
  let line = match (line.get_char(0), line.get_char(line.length() - 1)) {
    (Some(a), Some(b)) if quotes.contains(a) && quotes.contains(b) =>
      line.view(start_offset=1, end_offset=line.length() - 1).to_owned()
    _ => line
  }
  let marks = ['*', '#', '`', '_', '|', '<', '>', '[', ']', '{', '}']
  guard !line.iter().any(c => marks.contains(c)) else { None }
  Some(line)
}

///|
/// How many earlier happenings the prompt recalls.
const RECALLED : Int32 = 8

///|
/// Whole hours in `quarters`, quarter-hand-ticks.
fn crew_hours(quarters : Int64) -> Json {
  Json::number((quarters / (@core.HAND * @core.HOUR)).to_double())
}

///|
/// What the ship may know of a promoted officer: counts from this
/// crossing and the record, never an id, a name or anything a player wrote.
fn officer_facts(
  state : @core.State,
  crew : String,
  rank : Int64,
  tally : @core.Tally,
) -> Json {
  let record = state.ship.records.get(crew)
  let works = record.map(r => r.works).unwrap_or(0L)
  let regard = record.map(r => r.regard).unwrap_or(0L)
  {
    "rank": Json(@words.rank_name(rank)),
    "drive_hours": crew_hours(tally.drive),
    "hull_hours": crew_hours(tally.hull),
    "craft_hours": crew_hours(tally.craft),
    "watches_stood": Json::number(tally.watches_stood.to_double()),
    "watches_broken": Json::number(tally.watches_broken.to_double()),
    "works": Json::number(works.to_double()),
    "regard_hours": Json::number((regard / @core.REGARD_HOUR).to_double()),
  }
}

///|
/// The call asking the model for `voice`'s line about `about`, in `state`,
/// recalling what came before it in `story`.
pub fn Speech::call(
  self : Speech,
  voice : Voice,
  state : @core.State,
  story : Array[@core.Entry],
  about : @core.Entry,
) -> @llm.Call raise @prompt.PromptError {
  let ship = voice.epithet
  let earlier = story.filter(e => {
    e.seq < about.seq &&
    (weight(e.happening) is Some(_) || e.happening is Spoke(_))
  })
  let recent = earlier[(earlier.length() - RECALLED).max(0):]
    .iter()
    .map(e => @words.told(e.happening, you="", ship~))
    .collect()
  let ask = match state.crossing() {
    Some(c) => c.ask.map(@words.post_name)
    None => None
  }
  let system = self.prompts.render("system", {
    "epithet": Json(ship),
    "setting": Json(self.setting),
    "captain": Json(voice.captain),
    "voice": Json(voice.voice),
  })
  let officer = match about.happening {
    Promoted(crew~, rank~, tally~) => officer_facts(state, crew, rank, tally)
    _ => Json::null()
  }
  let user = self.prompts.render("user", {
    "happening": Json(@words.told(about.happening, you="", ship~)),
    "officer": officer,
    "readout": Json(@words.where_sentences(state)),
    "recent": Json(recent),
    "ask": match ask {
      Some(post) => Json::string(post)
      None => Json::null()
    },
  })
  @llm.Call::new(
    model=self.model,
    system=[system],
    user~,
    max_tokens=2000,
    reasoning_effort="low",
  )
}

///|
/// Writes one ship's lines. Holds what it has considered, so each
/// happening is weighed once, and when it last spoke.
pub struct Speaker {
  priv ship : String
  priv voice : Voice
  priv speech : Speech
  priv backend : @llm.Backend
  /// The newest story `seq` weighed.
  priv mut considered : Int64
  priv mut quiet_until : Int64
  priv mut speaking : Bool
}

///|
/// A speaker for `ship` that weighs only happenings after `from`, so a
/// restarted server does not answer old news.
pub fn Speaker::new(
  ship : String,
  voice : Voice,
  speech : Speech,
  backend : @llm.Backend,
  from~ : Int64,
) -> Speaker {
  {
    ship,
    voice,
    speech,
    backend,
    considered: from,
    quiet_until: 0,
    speaking: false,
  }
}

///|
/// The ship is writing a line now.
pub fn Speaker::speaking(self : Speaker) -> Bool {
  self.speaking
}

///|
/// Weigh what happened since the last step and, if something earns a
/// line, write it, check it with the gate, and append it at `clock()`. A
/// failed or blocked line is reported on stdout and leaves nothing.
pub async fn Speaker::step(
  self : Speaker,
  store : @store.Store,
  clock~ : () -> Int64,
) -> Unit {
  guard store.story(self.ship, after=self.considered) is Some(fresh) &&
    fresh.last() is Some(newest) else {
    return
  }
  self.considered = newest.seq
  guard worth(fresh, quiet_until=self.quiet_until) is Some(about) else {
    return
  }
  guard store.snapshot(self.ship) is Some(snapshot) &&
    store.story(self.ship, after=0) is Some(story) else {
    return
  }
  self.speaking = true
  defer {
    self.speaking = false
  }
  let report = (what : String) => {
    println("speech \{self.ship} @\{about.seq}: \{what}")
  }
  let started = @async.now()
  let line = try {
    let call = self.speech.call(self.voice, snapshot.state, story, about)
    let reply = self.backend.call(call)
    guard tidy(reply.text) is Some(line) else {
      report("unusable reply: \{reply.text}")
      return
    }
    let written = @async.now()
    match self.speech.gate.check(self.backend, line) {
      Clean => ()
      Violation(evidence) => {
        report("blocked (\{evidence}): \{line}")
        return
      }
    }
    report(
      "written in \{written - started} ms, gated in \{@async.now() - written} ms",
    )
    line
  } catch {
    err => {
      report("failed: \{err}")
      return
    }
  }
  let now = clock()
  store.speak(self.ship, line~, about=about.seq, now~)
  self.quiet_until = now + QUIET
}
