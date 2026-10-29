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
    Landed(..) | Made(..) => Some(2)
    Docked(..)
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
/// How many earlier happenings this crossing the prompt recounts.
const RECALLED : Int32 = 14

///|
/// How many of the ship's last lines the prompt shows, and `repeats`
/// compares against.
const SAID : Int32 = 5

///|
/// Whole hours in `quarters`, quarter-hand-ticks.
fn crew_hours(quarters : Int64) -> Json {
  Json::number((quarters / (@core.HAND * @core.HOUR)).to_double())
}

///|
/// What the ship may know of a promoted officer: counts from this
/// crossing and the record, and their handle, never an id, a name or
/// anything a player wrote.
fn officer_facts(
  state : @core.State,
  crew : String,
  rank : Int64,
  tally : @core.Tally,
) -> Json {
  let record = state.ship.records.get(crew)
  let works = record.map(r => r.works).unwrap_or(0L)
  let regard = record.map(r => r.regard).unwrap_or(0L)
  let handle = match state.crossing() {
    Some(c) => handles(c).get(crew)
    None => None
  }
  {
    "rank": Json(@words.rank_name(rank)),
    "drive_hours": crew_hours(tally.drive),
    "hull_hours": crew_hours(tally.hull),
    "craft_hours": crew_hours(tally.craft),
    "watches_stood": Json::number(tally.watches_stood.to_double()),
    "watches_broken": Json::number(tally.watches_broken.to_double()),
    "works": Json::number(works.to_double()),
    "regard_hours": Json::number((regard / @core.REGARD_HOUR).to_double()),
    "handle": match handle {
      Some(h) => Json::string(h)
      None => Json::null()
    },
  }
}

///|
/// The ship's last lines in `story`, oldest first.
fn said(story : Array[@core.Entry]) -> Array[String] {
  let lines = story.filter_map(e => {
    match e.happening {
      Spoke(line~, ..) => Some(line)
      _ => None
    }
  })
  lines[(lines.length() - SAID).max(0):].to_owned()
}

///|
/// The call asking the model for `voice`'s line about `about`, in `state`,
/// recounting what came before it this crossing in `story`, and the ship's
/// recent `thoughts` from its mind.
pub fn Speech::call(
  self : Speech,
  voice : Voice,
  state : @core.State,
  story : Array[@core.Entry],
  about : @core.Entry,
  thoughts~ : Array[String] = [],
) -> @llm.Call raise @prompt.PromptError {
  let ship = voice.epithet
  let names = match state.crossing() {
    Some(c) => handles(c)
    None => Map([])
  }
  let earlier = this_crossing(story).filter(e => {
    e.seq < about.seq && !(e.happening is Spoke(_))
  })
  let recent = earlier[(earlier.length() - RECALLED).max(0):]
    .iter()
    .map(e => recount(e.happening, names, ship~))
    .collect()
  let ask = match state.crossing() {
    Some(c) if c.phase != Arrived => c.ask.map(@words.post_name)
    _ => None
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
    "roster": Json(roster(state, story)),
    "recent": Json(recent),
    "thoughts": Json(thoughts),
    "said": Json(said(story)),
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
/// Lowercase words of `line`, without punctuation.
fn words_of(line : String) -> Array[String] {
  let out = []
  let word = StringBuilder()
  let flush = () => {
    let w = word.to_string()
    if w != "" {
      out.push(w)
    }
    word.reset()
  }
  for ch in line {
    if ch.is_ascii_alphabetic() || ch == '\'' {
      word.write_char(ch.to_ascii_lowercase())
    } else {
      flush()
    }
  }
  flush()
  out
}

///|
/// `line` opens like one of `earlier` (the same first three words), or
/// shares most of its longer words with one.
pub fn repeats(line : String, earlier : Array[String]) -> Bool {
  let these = words_of(line)
  let long = these.filter(w => w.length() > 3)
  earlier
  .iter()
  .any(other => {
    let those = words_of(other)
    let opens = these.length() >= 3 &&
      those.length() >= 3 &&
      these[:3] == those[:3]
    let shared = long.filter(w => those.contains(w)).length()
    opens || (long.length() >= 4 && shared * 5 >= long.length() * 3)
  })
}

///|
/// Why a ship said nothing.
pub(all) suberror Silent {
  /// The model replied PASS.
  Passed
  /// The reply was empty, too long or formatted.
  Unusable(String)
  /// The line opens like, or reuses most of, one of the ship's last lines.
  Repeated(String)
  Blocked(String, evidence~ : String)
} derive(Debug)

///|
pub impl Show for Silent with fn output(self, logger) {
  logger.write_string(
    match self {
      Passed => "kept quiet"
      Unusable(reply) => "unusable reply: \{reply}"
      Repeated(line) => "repeats itself: \{line}"
      Blocked(line, evidence~) => "blocked (\{evidence}): \{line}"
    },
  )
}

///|
/// `voice`'s line about `about`, written and passed by the gate. Raises
/// `Silent` if there is no line to say, or the backend's error.
pub async fn Speech::line(
  self : Speech,
  backend : @llm.Backend,
  voice : Voice,
  state : @core.State,
  story : Array[@core.Entry],
  about : @core.Entry,
  thoughts~ : Array[String] = [],
) -> @llm_gate.Cleared {
  let call = self.call(voice, state, story, about, thoughts~)
  let reply = backend.call(call)
  guard reply.text.trim() != "PASS" else { raise Passed }
  guard tidy(reply.text) is Some(line) else { raise Unusable(reply.text) }
  guard !repeats(line, said(story)) else { raise Repeated(line) }
  self.gate.clear(backend, line) catch {
    @llm_gate.Blocked(evidence) => raise Blocked(line, evidence~)
    err => raise err
  }
}

///|
/// Writes one ship's lines. Holds what it has considered, so each
/// happening is weighed once, and when it last spoke.
pub struct Speaker {
  priv ship : String
  priv voice : Voice
  priv speech : Speech
  priv backend : @llm.Backend
  /// The ship's mind is deciding, so its line waits to hear what it chose.
  priv busy : () -> Bool
  priv thoughts : () -> Array[String]
  /// The newest story `seq` weighed.
  priv mut considered : Int64
  priv mut quiet_until : Int64
  priv mut speaking : Bool
}

///|
/// A speaker for `ship` that weighs only happenings after `from`, so a
/// restarted server does not answer old news. It holds its line while
/// `busy`, and tells the model the ship's `thoughts`.
pub fn Speaker::new(
  ship : String,
  voice : Voice,
  speech : Speech,
  backend : @llm.Backend,
  from~ : Int64,
  busy~ : () -> Bool = () => false,
  thoughts~ : () -> Array[String] = () => [],
) -> Speaker {
  {
    ship,
    voice,
    speech,
    backend,
    busy,
    thoughts,
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
/// failed, blocked or repeated line, or the model passing, is reported on
/// stdout and leaves nothing.
pub async fn Speaker::step(
  self : Speaker,
  store : @store.Store,
  clock~ : () -> Int64,
) -> Unit {
  guard !(self.busy)() else { return }
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
  let line = self.speech.line(
    self.backend,
    self.voice,
    snapshot.state,
    story,
    about,
    thoughts=(self.thoughts)(),
  ) catch {
    err => {
      report("\{err}")
      return
    }
  }
  report("written in \{@async.now() - started} ms")
  let now = clock()
  store.speak(self.ship, line~, about=about.seq, now~)
  self.quiet_until = now + QUIET
}
