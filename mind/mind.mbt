// The ship's mind: a model that chooses the ship's asks, refits and
// promotions in character, with the scripted temperament as its fallback.
// See "the ship's mind" in docs/architecture.md.

///|
/// The prompts every ship's mind decides with.
pub struct Prompts {
  priv prompts : @prompt.Prompts
  priv setting : String
}

///|
/// `system`, `turn`, `muster` and `cruise` are the templates in
/// `content/mind/`; `setting` is `content/cast/prompts/setting.md`.
pub fn Prompts::new(
  system~ : String,
  turn~ : String,
  muster~ : String,
  cruise~ : String,
  setting~ : String,
) -> Prompts {
  {
    prompts: @prompt.Prompts::new(
      Map([
        ("system", system),
        ("turn", turn),
        ("muster", muster),
        ("cruise", cruise),
      ]),
    ),
    setting,
  }
}

///|
/// The templates in `content`.
pub async fn Prompts::load(content~ : String) -> Prompts {
  let read = async fn(path : String) {
    @fs.read_file("\{content}/\{path}").text()
  }
  Prompts::new(
    system=read("mind/system.md"),
    turn=read("mind/turn.md"),
    muster=read("mind/muster.md"),
    cruise=read("mind/cruise.md"),
    setting=read("cast/prompts/setting.md"),
  )
}

///|
/// How many earlier happenings a prompt recounts.
const RECOUNTED : Int32 = 16

///|
/// How many of its own thoughts the ship recalls.
const RECALLED : Int32 = 4

///|
fn Prompts::system(
  self : Prompts,
  voice : @speech.Voice,
  values : @core.Values,
) -> String raise {
  self.prompts.render("system", {
    "epithet": Json(voice.epithet),
    "setting": Json(self.setting),
    "captain": Json(voice.captain),
    "values": {
      "drive": Json::number(values.drive.to_double()),
      "hull": Json::number(values.hull.to_double()),
      "craft": Json::number(values.craft.to_double()),
    },
  })
}

///|
fn recent(
  state : @core.State,
  story : Array[@core.Entry],
  ship : String,
) -> Json {
  let names = match state.crossing() {
    Some(c) => @speech.handles(c)
    None => Map([])
  }
  let here = @speech.this_crossing(story)
  here[(here.length() - RECOUNTED).max(0):]
  .iter()
  .map(e => Json::string(@speech.recount(e.happening, names, ship~)))
  .collect()
  |> Json::array
}

///|
fn strings(xs : Array[String]) -> Json {
  Json::array(xs.map(Json::string))
}

///|
/// The words a reply uses for each ask.
fn ask_word(post : @core.Post?) -> String {
  match post {
    Some(Drive) => "drive"
    Some(Hull) => "hull"
    Some(Craft) => "crafts"
    None => "nothing"
  }
}

///|
/// The call asking the model what `voice`'s ship asks for and refits now.
pub fn Prompts::turn(
  self : Prompts,
  voice : @speech.Voice,
  values~ : @core.Values,
  model~ : String,
  state : @core.State,
  story : Array[@core.Entry],
  thoughts~ : Array[String],
) -> @llm.Call raise {
  guard state.crossing() is Some(c) else { fail("the ship is not underway") }
  let refits = @core.refits
    .filter(r => c.fit.can_refit(r))
    .map(r => {
      let level = c.fit.level(r) + 1L
      Json::object({
        "name": Json(@words.refit_name(r)),
        "effect": Json(
          "level \{level}, \{@words.refit_effect(r, level)} at that level",
        ),
      })
    })
  let user = self.prompts.render("turn", {
    "readout": strings(@words.where_sentences(state)),
    "roster": strings(@speech.roster(state, story)),
    "recent": recent(state, story, voice.epithet),
    "thoughts": strings(thoughts),
    "firing": Json::boolean(c.firing()),
    "ask": Json(ask_word(c.ask)),
    "refits": Json::array(refits),
    "refit": Json(c.fit.refit.map(@words.refit_name).unwrap_or("nothing")),
  })
  @llm.Call::new(
    model~,
    system=[self.system(voice, values)],
    user~,
    max_tokens=3000,
    reasoning_effort="low",
  )
}

///|
/// The call asking the model whom `voice`'s ship promotes at arrival, or,
/// while underway, in a promotion cycle.
pub fn Prompts::muster(
  self : Prompts,
  voice : @speech.Voice,
  values~ : @core.Values,
  model~ : String,
  state : @core.State,
  story : Array[@core.Entry],
  thoughts~ : Array[String],
  arrived~ : Bool,
) -> @llm.Call raise {
  guard state.crossing() is Some(c) else { fail("the ship is not underway") }
  let held = Array::make(@core.COMMANDER.to_int() + 1, 0L)
  for _, h in c.hands {
    held[h.rank.to_int()] += 1L
  }
  let room = []
  for rank, n in held {
    room.push("\{@words.rank_name(rank.to_int64())}: \{n} held.")
  }
  let user = self.prompts.render("muster", {
    "arrived": Json::boolean(arrived),
    "room": strings(room),
    "roster": strings(@speech.roster(state, story)),
    "recent": recent(state, story, voice.epithet),
    "thoughts": strings(thoughts),
  })
  @llm.Call::new(
    model~,
    system=[self.system(voice, values)],
    user~,
    max_tokens=3000,
    reasoning_effort="low",
  )
}

///|
/// The word a reply uses for each cruise.
fn cruise_word(cruise : Int64) -> String {
  match cruise {
    1000L => "hard"
    800L => "steady"
    600L => "easy"
    _ => "\{cruise} thousandths"
  }
}

///|
/// How many hands on the hull hold it even against `erosion`, to the
/// nearest tenth.
fn hands_even(erosion : Int64, repair : Int64) -> String {
  let tenths = (erosion * 10L + repair / 2L) / repair
  match tenths {
    10L => "one hand"
    t => "\{t / 10L}.\{t % 10L} hands"
  }
}

///|
fn cruise_share(cruise : Int64) -> String {
  match cruise {
    1000L => "all"
    800L => "four fifths"
    600L => "three fifths"
    _ => "\{cruise / 10L}%"
  }
}

///|
/// The officers aboard in port and the posts they named for departure.
fn port_crew(state : @core.State) -> String {
  let named = [0, 0, 0, 0]
  for _, o in state.officers {
    let i = match o.post {
      Some(Drive) => 0
      Some(Hull) => 1
      Some(Craft) => 2
      None => 3
    }
    named[i] += 1
  }
  let n = state.officers.length()
  let recruits = match state.ship.recruits {
    0L => ""
    1L => " 1 recruit works the ship's posts."
    r => " \{r} recruits work the ship's posts."
  }
  guard n > 0 else { return "No officers have signed on yet.\{recruits}" }
  let officers = if n == 1 { "1 officer is" } else { "\{n} officers are" }
  let unnamed = if named[3] > 0 { ", and \{named[3]} nothing yet" } else { "" }
  "\{officers} aboard. For departure, \{named[0]} named the drive, \{named[1]} the hull and \{named[2]} crafts\{unnamed}.\{recruits}"
}

///|
/// Whether a happening is about the ship rather than one hand. In port
/// there are no handles to name hands by.
fn voyage_wide(h : @core.Happening) -> Bool {
  h
  is (Departed
  | Began(_)
  | Docked(..)
  | Opened(_)
  | Met(_)
  | Missed(_)
  | Landed(..)
  | Asked(_)
  | Loaded
  | Cruised(_)
  | Bound(_))
}

///|
/// The worlds the ship has docked at, by name, with its crossings flown
/// at each docking.
fn calls(story : Array[@core.Entry]) -> Array[(String, Int64)] {
  story.filter_map(e => {
    guard e.happening is Docked(landing~, ..) else { None }
    Some((@ships.landing_leg(landing).1.name, landing.leg + 1L))
  })
}

///|
/// When the ship last docked at `world`, and how often it has, as a
/// sentence. The ship's last port is never a choice, so the last visit is
/// always two crossings ago or more.
fn visits(
  world : @ships.World,
  calls : Array[(String, Int64)],
  crossings : Int64,
) -> String {
  let at = calls.filter(c => c.0 == world.name)
  guard at.last() is Some((_, when)) else {
    return if world == @ships.leg(0).0 {
      "You were commissioned here, and have not docked here since."
    } else {
      "You have never docked here."
    }
  }
  let times = match at.length() {
    1 => "once"
    2 => "twice"
    n => "\{n} times"
  }
  "You have docked here \{times}, last \{crossings - when} crossings ago."
}

///|
/// The name the ship knows another ship by.
fn epithet(state : @core.State) -> String {
  @ships.profile_named(state.profile)
  .bind(p => p.title)
  .map(t => t.epithet)
  .unwrap_or(state.profile)
}

///|
/// What the other ships of the fleet are doing at `world`, as sentences:
/// in port there, or bound there.
fn fleet_at(world : @ships.World, fleet : Array[@core.State]) -> Array[String] {
  fleet.filter_map(s => {
    let name = epithet(s)
    let bound = @ships.bound_for(s)
    match s.leg {
      InPort(_) if @ships.origin(s.ship) == world => {
        let leaves = s.launch().unwrap().ready_at - s.at
        Some("\{name} is in port there, leaving \{@words.soon_words(leaves)}.")
      }
      InPort(_) if bound == Some(world) =>
        Some(
          "\{name} is in port at \{@ships.origin(s.ship).name}, and has chosen to go there next.",
        )
      Underway(crossing=c, ..) if bound == Some(world) =>
        match c.forecast() {
          Some(at) =>
            Some(
              "\{name} is bound there, arriving \{@words.in_words(at - c.t)}.",
            )
          None => Some("\{name} is bound there.")
        }
      _ => None
    }
  })
}

///|
/// The call asking the model, in port, where `voice`'s ship goes next, how
/// fast it coasts there, and whether it asks the crew to load stores or
/// mend. `fleet` is the other ships, as they are now.
pub fn Prompts::cruise(
  self : Prompts,
  voice : @speech.Voice,
  values~ : @core.Values,
  model~ : String,
  profile~ : @ships.Profile,
  state : @core.State,
  story : Array[@core.Entry],
  thoughts~ : Array[String],
  fleet~ : Array[@core.State],
) -> @llm.Call raise {
  guard state.leg is InPort(port~) else { fail("the ship is not in port") }
  let ship = state.ship
  let here = @ships.origin(ship)
  let hours = (ticks : Int64) => (ticks + 1800L) / 3600L
  let load = state.launch().unwrap().load
  let called = calls(story)
  let courses = @ships.choices(ship).map(world => {
    let distance_ly = here.distance_to(world)
    let cruises = @ships.cruises.map(cruise => {
      let plan = profile.next_plan(distance_ly~, coils=ship.fit.coils, cruise~)
      Json::object({
        "name": Json(cruise_word(cruise)),
        "share": Json(cruise_share(cruise)),
        "hands": Json(hands_even(plan.erosion(ship.fit), ship.fit.repair)),
        "hours": Json(
          "\{hours(plan.fastest())} to \{hours(plan.slowest())} hours",
        ),
        "wear": Json("\{plan.coast_wear(ship.fit) * 100L / @core.HULL_FULL}%"),
        "current": Json::boolean(cruise == ship.cruise),
      })
    })
    // What is loaded already counts toward this leg's stores.
    let left = (port.stores + @ships.stores_for(ship, world) - port.needed).max(
      0L,
    )
    let tenths = (distance_ly * 10.0).round().to_int64()
    Json::object({
      "name": Json(world.name),
      "star": Json(world.star),
      "distance": Json("\{tenths / 10L}.\{tenths % 10L} light-years"),
      "leaves": Json(
        "With the crew posted as they are, you would leave \{@words.soon_words((left + load - 1L) / load)}.",
      ),
      "visits": Json(visits(world, called, ship.crossings)),
      "fleet": strings(fleet_at(world, fleet)),
      "cruises": Json::array(cruises),
      "current": Json::boolean(ship.bound == Some(world.name)),
    })
  })
  let last = @speech.this_crossing(story)
  let user = self.prompts.render("cruise", {
    "here": Json(here.name),
    "star": Json(here.star),
    "came_from": match @ships.came_from(ship) {
      Some(w) => Json::string(w.name)
      None => Json::null()
    },
    "short": Json::boolean(@ships.flew_short(ship)),
    "hull": Json("\{ship.hull * 100L / @core.HULL_FULL}%"),
    "launch": strings(@words.where_sentences(state)[1:].to_owned()),
    "crew": Json(port_crew(state)),
    "courses": Json::array(courses),
    "recent": last
    .filter(e => voyage_wide(e.happening))
    .iter()
    .map(e => {
      Json::string(@speech.recount(e.happening, Map([]), ship=voice.epithet))
    })
    .collect()
    |> Json::array,
    "thoughts": strings(thoughts),
  })
  @llm.Call::new(
    model~,
    system=[self.system(voice, values)],
    user~,
    max_tokens=3000,
    reasoning_effort="low",
  )
}

///|
/// A world's name as a reply may write it: any case, with or without its
/// article.
fn plain(name : String) -> String {
  let n = name.trim().to_owned().to_lower()
  if n.has_prefix("the ") {
    n.view(start_offset=4).to_owned()
  } else {
    n
  }
}

///|
/// The world `reply` chooses to leave for next, among `ship`'s choices.
/// Raises `Unreadable` without one of them by name.
pub fn decode_course(
  reply : String,
  ship : @core.Ship,
) -> @ships.World raise Unreadable {
  let o = object(reply)
  guard o.get("course") is Some(String(name)) else {
    raise Unreadable("no course in the reply")
  }
  guard @ships.choices(ship)
    .iter()
    .find_first(w => plain(w.name) == plain(name))
    is Some(world) else {
    raise Unreadable("no such course: \{name}")
  }
  world
}

///|
/// The cruise the model chose in `reply`, and its reason. Raises
/// `Unreadable` without one of `@ships.cruises` by name.
pub fn decode_cruise(reply : String) -> (Int64, String) raise Unreadable {
  let o = object(reply)
  let name = match o.get("cruise") {
    Some(String(s)) => s.trim().to_owned().to_lower()
    _ => raise Unreadable("no cruise in the reply")
  }
  guard @ships.cruises.iter().find_first(c => cruise_word(c) == name)
    is Some(cruise) else {
    raise Unreadable("no such cruise: \{name}")
  }
  (cruise, thought_of(o))
}

///|
pub(all) suberror Unreadable {
  Unreadable(String)
} derive(Debug)

///|
pub impl Show for Unreadable with fn output(self, logger) {
  let Unreadable(why) = self
  logger.write_string(why)
}

///|
/// The JSON object from the reply's first `{` to its last `}`.
fn object(reply : String) -> Map[String, Json] raise Unreadable {
  let unreadable = Unreadable(
    "no object in the reply: \{reply.view(end_offset=reply.length().min(200))}",
  )
  guard reply.find("{") is Some(start) &&
    reply.rev_find("}") is Some(end) &&
    end > start else {
    raise unreadable
  }
  let parsed = @json.parse(reply[start:end + 1]) catch { _ => raise unreadable }
  guard parsed is Object(o) else { raise unreadable }
  o
}

///|
fn thought_of(o : Map[String, Json]) -> String {
  match o.get("thought") {
    Some(String(s)) => s.trim().to_owned()
    _ => ""
  }
}

///|
/// What the model chose for a turn: the acts, and the ship's private reason.
pub(all) struct Choice {
  acts : Array[@ships.Act]
  thought : String
} derive(Debug, Eq)

///|
/// The turn in `reply` for crossing `c`. The ask is always made, so the log
/// records that the ship reconsidered; the refit only if it changes and
/// can be built. Raises `Unreadable` without a valid ask.
fn ask_of(o : Map[String, Json]) -> @core.Post? raise Unreadable {
  match o.get("ask") {
    Some(String("drive")) => Some(Drive)
    Some(String("hull")) => Some(Hull)
    Some(String("crafts" | "craft")) => Some(Craft)
    Some(String("nothing" | "none")) | Some(Null) => None
    _ =>
      raise Unreadable("no ask in the reply: \{Json(o.get("ask")).stringify()}")
  }
}

///|
/// What the ship asks for in port, from a cruise reply. Raises `Unreadable`
/// without a readable `ask`.
pub fn decode_port_ask(reply : String) -> @core.Post? raise Unreadable {
  ask_of(object(reply))
}

///|
pub fn decode_turn(
  reply : String,
  c : @core.Crossing,
) -> Choice raise Unreadable {
  let o = object(reply)
  let ask = ask_of(o)
  let refit = match o.get("refit") {
    Some(String(name)) =>
      match @core.refits.iter().find_first(r => @words.refit_name(r) == name) {
        Some(r) if c.fit.can_refit(r) => Some(Some(r))
        Some(_) => None
        None => if name == "none" { Some(None) } else { None }
      }
    _ => None
  }
  let acts : Array[@ships.Act] = [Ask(ask)]
  if refit is Some(r) && r != c.fit.refit {
    acts.push(Refit(r))
  }
  { acts, thought: thought_of(o), }
}

///|
/// The handles the model promoted in `reply`, as crew ids by `names`, and
/// its reason. Unknown handles are dropped. Raises `Unreadable` without a
/// list of promotions.
pub fn decode_muster(
  reply : String,
  names : Map[String, String],
) -> (Array[String], String) raise Unreadable {
  let o = object(reply)
  guard o.get("promote") is Some(Array(picks)) else {
    raise Unreadable("no promotions in the reply")
  }
  let by_handle : Map[String, String] = Map([])
  for crew, handle in names {
    by_handle[handle] = crew
  }
  let crew = []
  for p in picks {
    guard p is String(s) else { continue }
    let handle = s.trim().to_owned()
    let handle = if handle.has_prefix("Hand ") {
      handle[5:].to_owned()
    } else {
      handle
    }
    if by_handle.get(handle) is Some(id) {
      crew.push(id)
    }
  }
  (crew, thought_of(o))
}
