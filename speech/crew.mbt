// What a ship's model may know of its crew: a handle per hand and facts
// counted from the crossing, never a crew id or anything a player wrote.

///|
/// A handle per crew member who has held a post this crossing, in the
/// order they joined: "A", "B", ... then "A2". Stable for the crossing, and
/// private to the model: players never see it.
pub fn handles(c : @core.Crossing) -> Map[String, String] {
  let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  let out : Map[String, String] = Map([])
  let mut i = 0
  for crew, _ in c.tallies {
    let letter = letters.get_char(i % 26).unwrap().to_string()
    let round = i / 26
    out[crew] = if round == 0 { letter } else { "\{letter}\{round + 1}" }
    i += 1
  }
  out
}

///|
/// The story since the ship last left port, or all of it if it never has.
pub fn this_crossing(story : Array[@core.Entry]) -> Array[@core.Entry] {
  let mut from = 0
  for i, e in story {
    if e.happening is Departed {
      from = i
    }
  }
  story[from:].to_owned()
}

///|
/// How many times each crew member took the post the ship was asking for,
/// after it asked, in `story`.
pub fn answered(story : Array[@core.Entry]) -> Map[String, Int64] {
  let out : Map[String, Int64] = Map([])
  let mut ask : @core.Post? = None
  for e in story {
    match e.happening {
      Asked(post~) => ask = post
      Took(crew~, post~) if ask == Some(post) =>
        out[crew] = out.get(crew).unwrap_or(0L) + 1L
      _ => ()
    }
  }
  out
}

///|
/// Whole hours in `quarters`, quarter-hand-ticks.
fn hours_of(quarters : Int64) -> Int64 {
  quarters / (@core.HAND * @core.HOUR)
}

///|
/// One line per crew member this crossing, by handle: rank, post, watch,
/// hours on each post, watches, asks answered, works and regard on record.
pub fn roster(state : @core.State, story : Array[@core.Entry]) -> Array[String] {
  guard state.crossing() is Some(c) else { return [] }
  let names = handles(c)
  let answers = answered(this_crossing(story))
  let out = []
  for crew, t in c.tallies {
    let handle = names.get(crew).unwrap_or("?")
    let rank = @words.rank_name(state.rank(crew))
    let where_ = match c.hands.get(crew) {
      None => "left the crew this crossing"
      Some(h) => {
        let post = match h.post {
          Craft => "at crafts (\{@words.craft_name(h.craft)})"
          p => "on \{@words.post_name(p)}"
        }
        let watch = match h.watch {
          Some(w) =>
            ", standing a watch for \{@words.about(w.until - c.t)} more"
          None => ""
        }
        "\{post}\{watch}"
      }
    }
    let record = state.ship.records.get(crew)
    let works = record.map(r => r.works).unwrap_or(0L) +
      (record.map(r => r.carry).unwrap_or(0L) + t.work) / @core.WORK_SIZE
    let regard = record.map(r => r.regard).unwrap_or(0L) + t.regard
    let served = c.served(crew) / @core.HOUR
    let too_new = state.rank(crew) == @core.ENSIGN && !@ships.eligible(c, crew)
    out.push(
      "Hand \{handle}, \{rank}: \{where_}. This crossing \{hours_of(t.drive)} h on the drive, \{hours_of(t.hull)} h on the hull, \{hours_of(t.craft)} h at crafts; watches stood \{t.watches_stood}, broken \{t.watches_broken}; answered your ask \{@words.plural(answers.get(crew).unwrap_or(0L), "time", "times")}. Works finished in all: \{works}. Regard: \{regard / @core.REGARD_HOUR} h. Served \{served} h aboard.\{if too_new { " Too new to promote." } else { "" }}",
    )
  }
  out
}

///|
/// A happening as the model is told it: crew by handle, the ship as "you".
pub fn recount(
  h : @core.Happening,
  names : Map[String, String],
  ship~ : String,
) -> String {
  let who = (crew : String) => "Hand \{names.get(crew).unwrap_or("?")}"
  match h {
    Took(crew~, post=Craft) => "\{who(crew)} went to crafts."
    Took(crew~, post~) => "\{who(crew)} took \{@words.post_name(post)}."
    Left(crew~) => "\{who(crew)} left the crew."
    Stood(crew~) => "\{who(crew)} stood a watch to its end."
    Finished(crew~) => "\{who(crew)} finished a work."
    Promoted(crew~, rank~, ..) =>
      "You promoted \{who(crew)} to \{@words.rank_name(rank)}."
    Asked(post=Some(post)) =>
      "You asked for hands on \{@words.post_name(post)}."
    Asked(post=None) => "You stopped asking for hands."
    Spoke(line~, ..) => "You said: \{line}"
    h => @words.told(h, you="", ship~)
  }
}
