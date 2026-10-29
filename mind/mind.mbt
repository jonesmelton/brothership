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
/// `system`, `turn` and `muster` are the templates in `content/mind/`;
/// `setting` is `content/cast/prompts/setting.md`.
pub fn Prompts::new(
  system~ : String,
  turn~ : String,
  muster~ : String,
  setting~ : String,
) -> Prompts {
  {
    prompts: @prompt.Prompts::new(
      Map([("system", system), ("turn", turn), ("muster", muster)]),
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
pub fn decode_turn(
  reply : String,
  c : @core.Crossing,
) -> Choice raise Unreadable {
  let o = object(reply)
  let ask : @core.Post? = match o.get("ask") {
    Some(String("drive")) => Some(Drive)
    Some(String("hull")) => Some(Hull)
    Some(String("crafts" | "craft")) => Some(Craft)
    Some(String("nothing" | "none")) | Some(Null) => None
    _ =>
      raise Unreadable("no ask in the reply: \{Json(o.get("ask")).stringify()}")
  }
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
