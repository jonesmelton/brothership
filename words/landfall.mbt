// The account of a docking, built from the story alone, so replay never
// calls a model. The roll call is pulled from this page, never pushed as an
// announcement. See docs/design.md.

///|
/// Time at the worlds, coarse once it is over: days under a tenth of a
/// year, months under a year and a half, then years to a tenth.
fn years_span(years : Double) -> String {
  let days = years * 365.25
  if days < 1.0 {
    "under a day"
  } else if years < 0.1 {
    plural(days.round().to_int64(), "day", "days")
  } else if years < 1.5 {
    plural((years * 12.0).round().to_int64(), "month", "months")
  } else {
    "\{fixed(years, 1)} years"
  }
}

///|
fn aboard_span(ticks : Int64) -> String {
  if ticks < @core.HOUR {
    "under an hour"
  } else {
    plural((ticks + @core.HOUR / 2L) / @core.HOUR, "hour", "hours")
  }
}

///|
/// How many times each crew member took the post the ship was asking for,
/// after it asked, in `story`.
pub fn asks_answered(story : Array[@core.Entry]) -> Map[String, Int64] {
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
/// The crossing that ended at the newest docking in `story`: its entries
/// from departure to the docking, the docking, and what it carried.
fn last_landfall(
  story : Array[@core.Entry],
) -> (Array[@core.Entry], @core.Entry, Int64, @core.Landing)? {
  let mut at = -1
  for i, e in story {
    if e.happening is Docked(..) {
      at = i
    }
  }
  guard at >= 0 else { return None }
  guard story[at].happening is Docked(recruits~, landing~) else { return None }
  let mut from = 0
  for i in 0..<at {
    if story[i].happening is Departed {
      from = i
    }
  }
  Some((story[from:at].to_owned(), story[at], recruits, landing))
}

///|
/// The Landfall section: where the newest docking came in, the hours aboard
/// against the years at the worlds, the roll call of the muster, who
/// answered the ship's asks, and what the crossing delivered. One sentence
/// says there has been none yet. `now` is Unix seconds.
pub fn landfall_sentences(
  story : Array[@core.Entry],
  you~ : String,
  now~ : Int64,
) -> Array[String] {
  guard last_landfall(story) is Some((crossing, docked, recruits, landing)) else {
    return ["No landfall yet. The ship has not finished a crossing."]
  }
  let (from, to) = @ships.landing_leg(landing)
  let lines = [
    "Made \{to.name} from \{from.name}: \{aboard_span(landing.aboard)} aboard, \{years_span(@ships.span_of(landing.plan))} at the worlds.",
    "Landfall was \{ago((now - docked.at).max(0L))}.",
  ]
  let mut arrived = 0
  for i, e in crossing {
    if e.happening is Began(phase=Arrived) {
      arrived = i
    }
  }
  let muster : Array[String] = []
  for e in crossing[arrived:] {
    if e.happening is Promoted(crew~, rank~, ..) {
      let who = if crew == you { "you" } else { "a hand" }
      muster.push("\{who} to \{rank_name(rank)}")
    }
  }
  if muster.is_empty() {
    lines.push("Nobody was promoted at the muster.")
  } else {
    lines.push("Promoted at the muster: \{muster.join(", ")}.")
  }
  let mut asks = 0L
  for e in crossing {
    if e.happening is Asked(post=Some(_)) {
      asks += 1L
    }
  }
  let answers = asks_answered(crossing)
  let mut answered = 0L
  for _, n in answers {
    answered += n
  }
  let yours = answers.get(you).unwrap_or(0L)
  if asks == 0L {
    lines.push("The ship asked for nothing this crossing.")
  } else if answered == 0L {
    lines.push("Nobody answered the ship's \{plural(asks, "ask", "asks")}.")
  } else {
    let share = if yours == 0L {
      "none of them by you"
    } else if yours == answered {
      "all of them by you"
    } else {
      "\{yours} of them by you"
    }
    lines.push(
      "The ship's \{plural(asks, "ask", "asks")} were answered \{plural(answered, "time", "times")}, \{share}.",
    )
  }
  let works = match landing.works {
    0L => "no works"
    n => plural(n, "work", "works")
  }
  let gained = match recruits {
    0L => "no recruits"
    n => plural(n, "recruit", "recruits")
  }
  lines.push("The crossing delivered \{works} and gained \{gained}.")
  lines
}

///|
/// For "while you were away" on the Voyage page: one sentence pointing to
/// the landfall when a docking fell after `after` and no later than `upto`.
pub fn landfall_away(
  story : Array[@core.Entry],
  after~ : Int64,
  upto~ : Int64,
) -> Array[String] {
  guard last_landfall(story) is Some((_, docked, _, landing)) else { return [] }
  guard docked.seq > after && docked.seq <= upto else { return [] }
  let (_, to) = @ships.landing_leg(landing)
  ["Landfall at \{to.name}. The account is under Landfall on this page."]
}
