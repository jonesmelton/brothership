///|
/// One ship's mind on the server. Holds what it last weighed, so each
/// moment is decided once, and its recent thoughts, which the speaker reads.
pub struct Mind {
  priv ship : String
  priv profile : @ships.Profile
  priv voice : @speech.Voice
  priv prompts : Prompts
  priv model : String
  priv backend : @llm.Backend
  /// Refit levels when the ship last chose a refit, so a landed refit is
  /// a reason to choose again.
  priv mut weighed : Array[Int64]?
  /// The arrival, in Unix seconds, last mustered.
  priv mut mustered : Int64?
  /// Unix seconds of the last mid-crossing promotion cycle.
  priv mut cycled : Int64?
  /// The port stay, by when it began in Unix seconds, last given a cruise.
  priv mut cruised : Int64?
  priv mut thinking : Bool
  priv thoughts : Array[String]
}

///|
/// Longest a turn waits for the model before the script takes it, in
/// milliseconds.
const TURN_MS : Int32 = 120_000

///|
/// Longest a muster waits for the model, in milliseconds: well inside
/// `MIND_WAIT`, after which the clock docks by script.
const MUSTER_MS : Int32 = 180_000

///|
/// Game seconds between mid-crossing promotion cycles.
const CYCLE_GAP : Int64 = 1800L

///|
pub fn Mind::new(
  ship : String,
  profile : @ships.Profile,
  voice : @speech.Voice,
  prompts : Prompts,
  model~ : String,
  backend : @llm.Backend,
) -> Mind {
  {
    ship,
    profile,
    voice,
    prompts,
    model,
    backend,
    weighed: None,
    mustered: None,
    cycled: None,
    cruised: None,
    thinking: false,
    thoughts: [],
  }
}

///|
/// The ship is waiting on its model now.
pub fn Mind::thinking(self : Mind) -> Bool {
  self.thinking
}

///|
/// The ship's latest thoughts, oldest first, as the speaker is told them.
pub fn Mind::thoughts(self : Mind) -> Array[String] {
  self.thoughts[(self.thoughts.length() - RECALLED).max(0):].to_owned()
}

///|
/// The thoughts a turn recalls: fewer, since a ship fed its own reasons
/// repeats them.
fn Mind::recalled(self : Mind) -> Array[String] {
  self.thoughts[(self.thoughts.length() - 2).max(0):].to_owned()
}

///|
fn Mind::remember(self : Mind, did : String, why : String) -> Unit {
  let line = if why == "" { did } else { "\{did} You thought: \{why}" }
  self.thoughts.push(line)
  if self.thoughts.length() > RECALLED * 4 {
    self.thoughts.remove(0) |> ignore
  }
}

///|
fn Mind::report(self : Mind, what : String) -> Unit {
  println("mind \{self.ship}: \{what}")
}

///|
fn levels(fit : @core.Fit) -> Array[Int64] {
  @core.refits.map(r => fit.level(r))
}

///|
/// The turn as the ship would recall it.
fn did(acts : Array[@ships.Act]) -> String {
  acts
  .map(act => {
    match act {
      Ask(Some(post)) => "You asked for hands on \{@words.post_name(post)}."
      Ask(None) => "You asked for nothing in particular."
      Refit(Some(r)) => "You set the engineers to \{@words.refit_name(r)}."
      Refit(None) => "You set the engineers to nothing."
    }
  })
  .join(" ")
}

///|
/// Whether the crossing `c`, with the ship last reconsidering at `spoke`,
/// wants a turn from the mind.
fn Mind::due(self : Mind, c : @core.Crossing, spoke : @core.Moment?) -> Bool {
  if spoke != Some(c.moment()) {
    return true
  }
  c.fit.refit is None &&
  @core.refits.iter().any(r => c.fit.can_refit(r)) &&
  self.weighed != Some(levels(c.fit))
}

///|
/// Look at the ship and, if it is due a turn or a muster, ask the model
/// and append what it chose at `clock()`. A failed, late or unreadable
/// reply falls back to the scripted temperament, so the ship always acts.
pub async fn Mind::step(
  self : Mind,
  store : @store.Store,
  clock~ : () -> Int64,
) -> Unit {
  guard store.snapshot(self.ship) is Some(snapshot) &&
    store.story(self.ship, after=0) is Some(story) else {
    return
  }
  let state = snapshot.state
  if state.leg is InPort(since~) && self.cruised != Some(since) {
    self.cruised = Some(since)
    self.course(store, state, story, clock~)
    return
  }
  guard state.leg is Underway(crossing=c, spoke~) else { return }
  match @ships.arrived_at(state) {
    Some(at) if self.mustered != Some(at) => {
      self.mustered = Some(at)
      self.muster(store, state, c, story, clock~)
    }
    Some(_) => ()
    None if self.due(c, spoke) =>
      self.turn(store, state, c, spoke, story, clock~)
    None => {
      let now = clock()
      let ready = match self.cycled {
        None => true
        Some(at) => now - at >= CYCLE_GAP
      }
      if ready && @ships.bottom_heavy(c, officer=_ => true) {
        self.cycled = Some(now)
        self.cycle(store, state, c, story, clock~)
      }
    }
  }
}

///|
async fn Mind::turn(
  self : Mind,
  store : @store.Store,
  state : @core.State,
  c : @core.Crossing,
  spoke : @core.Moment?,
  story : Array[@core.Entry],
  clock~ : () -> Int64,
) -> Unit {
  self.thinking = true
  defer {
    self.thinking = false
  }
  let started = @async.now()
  let choice = try {
    let call = self.prompts.turn(
      self.voice,
      values=self.profile.values,
      model=self.model,
      state,
      story,
      thoughts=self.recalled(),
    )
    match @async.with_timeout_opt(TURN_MS, () => self.backend.call(call)) {
      Some(reply) => Some(decode_turn(reply.text, c))
      None => {
        self.report("no reply in \{TURN_MS} ms")
        None
      }
    }
  } catch {
    err => {
      self.report("failed: \{err}")
      None
    }
  }
  let (acts, why, how) = match choice {
    Some(ch) => (ch.acts, ch.thought, "chose")
    None => {
      let acts = self.profile.temperament.turn(c, spoke)
      // The scripted turn asks only at a new moment; always mark this one.
      let acts = if acts.iter().any(a => a is Ask(_)) {
        acts
      } else {
        [Ask(c.ask), ..acts]
      }
      (acts, "", "fell back to its temperament")
    }
  }
  let taken = store.decide(self.ship, acts, moment=c.moment(), now=clock())
  guard taken else {
    self.report("the moment passed while it thought; weighing again")
    return
  }
  self.weighed = Some(levels(c.fit))
  let line = did(acts)
  self.remember(line, why)
  self.report("\{how} in \{@async.now() - started} ms: \{line} \{why}")
}

///|
async fn Mind::muster(
  self : Mind,
  store : @store.Store,
  state : @core.State,
  c : @core.Crossing,
  story : Array[@core.Entry],
  clock~ : () -> Int64,
) -> Unit {
  self.thinking = true
  defer {
    self.thinking = false
  }
  let names = @speech.handles(c)
  let started = @async.now()
  let chosen = try {
    let call = self.prompts.muster(
      self.voice,
      values=self.profile.values,
      model=self.model,
      state,
      story,
      thoughts=self.thoughts(),
      arrived=true,
    )
    match @async.with_timeout_opt(MUSTER_MS, () => self.backend.call(call)) {
      Some(reply) => Some(decode_muster(reply.text, names))
      None => {
        self.report("no muster in \{MUSTER_MS} ms")
        None
      }
    }
  } catch {
    err => {
      self.report("muster failed: \{err}")
      None
    }
  }
  let (picks, why, how) = match chosen {
    Some((picks, why)) => (picks, why, "mustered")
    None =>
      (
        @ships.promotions(c, officer=_ => true).map(p => p.0),
        "",
        "mustered by its temperament",
      )
  }
  guard store.muster(self.ship, picks, now=clock()) is Some(promoted) else {
    self.report("docked by script before the muster landed")
    return
  }
  let line = if promoted.is_empty() {
    "You promoted nobody at arrival."
  } else {
    let who = promoted.map(p => {
      "Hand \{names.get(p.0).unwrap_or("?")} to \{@words.rank_name(p.1)}"
    })
    "At arrival you promoted \{who.join(", ")}."
  }
  self.remember(line, why)
  self.report("\{how} in \{@async.now() - started} ms: \{line} \{why}")
}

///|
async fn Mind::cycle(
  self : Mind,
  store : @store.Store,
  state : @core.State,
  c : @core.Crossing,
  story : Array[@core.Entry],
  clock~ : () -> Int64,
) -> Unit {
  self.thinking = true
  defer {
    self.thinking = false
  }
  let names = @speech.handles(c)
  let started = @async.now()
  let chosen = try {
    let call = self.prompts.muster(
      self.voice,
      values=self.profile.values,
      model=self.model,
      state,
      story,
      thoughts=self.thoughts(),
      arrived=false,
    )
    match @async.with_timeout_opt(MUSTER_MS, () => self.backend.call(call)) {
      Some(reply) => Some(decode_muster(reply.text, names))
      None => {
        self.report("no cycle in \{MUSTER_MS} ms")
        None
      }
    }
  } catch {
    err => {
      self.report("cycle failed: \{err}")
      None
    }
  }
  let (picks, why, how) = match chosen {
    Some((picks, why)) => (picks, why, "promoted underway")
    None =>
      (
        @ships.first_ensign(c, officer=_ => true).map(p => p.0),
        "",
        "promoted underway by its temperament",
      )
  }
  guard store.promote(self.ship, picks, now=clock()) is Some(promoted) else {
    self.report("the ship was no longer underway")
    return
  }
  let line = if promoted.is_empty() {
    "Underway you promoted nobody."
  } else {
    let who = promoted.map(p => {
      "Hand \{names.get(p.0).unwrap_or("?")} to \{@words.rank_name(p.1)}"
    })
    "Underway you promoted \{who.join(", ")}."
  }
  self.remember(line, why)
  self.report("\{how} in \{@async.now() - started} ms: \{line} \{why}")
}

///|
async fn Mind::course(
  self : Mind,
  store : @store.Store,
  state : @core.State,
  story : Array[@core.Entry],
  clock~ : () -> Int64,
) -> Unit {
  self.thinking = true
  defer {
    self.thinking = false
  }
  let started = @async.now()
  let chosen = try {
    let call = self.prompts.cruise(
      self.voice,
      values=self.profile.values,
      model=self.model,
      profile=self.profile,
      state,
      story,
      thoughts=self.recalled(),
    )
    match @async.with_timeout_opt(TURN_MS, () => self.backend.call(call)) {
      Some(reply) => Some(decode_cruise(reply.text))
      None => {
        self.report("no cruise in \{TURN_MS} ms")
        None
      }
    }
  } catch {
    err => {
      self.report("cruise failed: \{err}")
      None
    }
  }
  let (cruise, why, how) = match chosen {
    Some((cruise, why)) => (cruise, why, "set its cruise")
    None => {
      let distance_ly = @ships.hop(state.ship.crossings)
      (
        self.profile.temperament.cruise(state.ship, distance_ly~),
        "",
        "set its cruise by its temperament",
      )
    }
  }
  guard store.cruise(self.ship, cruise, now=clock()) else {
    self.report("departed before the cruise landed")
    return
  }
  let at = if cruise == @core.CRUISE_FULL {
    "your full γ cap"
  } else {
    "\{cruise_share(cruise)} of your γ cap"
  }
  let line = "In port you chose to coast at \{at}."
  self.remember(line, why)
  self.report("\{how} in \{@async.now() - started} ms: \{line} \{why}")
}
