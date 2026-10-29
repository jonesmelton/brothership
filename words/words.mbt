// The check-in as sentences. Every fact on the screen is one of these first;
// the layout only arranges them. See docs/accessibility.md.

///|
/// A span in words that coarsen with length and do not tick: under an
/// hour, about an hour, whole hours to 6, the nearest 3 hours to 36, then
/// whole days. See research/liveship-travel-math.md, section 11.
pub fn about(seconds : Int64) -> String {
  if seconds < 3600L {
    "under an hour"
  } else if seconds < 5400L {
    "about an hour"
  } else if seconds < 6L * 3600L {
    "about \{(seconds + 1800L) / 3600L} hours"
  } else if seconds < 36L * 3600L {
    "about \{(seconds + 5400L) / 10800L * 3L} hours"
  } else {
    "about \{(seconds + 43200L) / 86400L} days"
  }
}

///|
/// When something `seconds` away happens, in the words of `about`.
pub fn in_words(seconds : Int64) -> String {
  if seconds < 3600L {
    "within the hour"
  } else {
    "in \{about(seconds)}"
  }
}

///|
/// A wait in port in words: the nearest 5 minutes, never ticking by the
/// minute.
fn soon_words(seconds : Int64) -> String {
  let fives = (seconds + 150L) / 300L
  if fives <= 0L {
    "any moment"
  } else if fives * 5L >= 60L {
    in_words(seconds)
  } else {
    "in about \{fives * 5L} minutes"
  }
}

///|
fn clamp_rank(rank : Int64) -> Int32 {
  rank.max(0L).min(@core.COMMANDER).to_int()
}

///|
/// A rank as a label: sentence case. Ranks outside 0 to 4 clamp.
pub fn rank_title(rank : Int64) -> String {
  [
    "Ensign", "Lieutenant junior grade", "Lieutenant", "Lieutenant commander", "Commander",
  ][clamp_rank(rank)]
}

///|
/// A rank inside a sentence: lowercase. Ranks outside 0 to 4 clamp.
pub fn rank_name(rank : Int64) -> String {
  rank_title(rank).to_lower()
}

///|
/// A rank's abbreviation: ENS, LTJG, LT, LCDR or CDR. For labels, never
/// for prose.
pub fn rank_abbreviation(rank : Int64) -> String {
  ["ENS", "LTJG", "LT", "LCDR", "CDR"][clamp_rank(rank)]
}

///|
/// A rank's insignia: one mark that repeats the abbreviation, so it is
/// decoration for a screen reader.
pub fn rank_insignia(rank : Int64) -> String {
  [
    "\u{25cb}", "\u{25cf}", "\u{25cf}\u{25cf}", "\u{25cf}\u{25cf}\u{25cf}", "\u{2605}",
  ][clamp_rank(rank)]
}

///|
pub fn post_name(post : @core.Post) -> String {
  match post {
    Drive => "the drive"
    Hull => "the hull"
    Craft => "crafts"
  }
}

///|
pub fn craft_name(craft : @core.Craft) -> String {
  match craft {
    Engineer => "engineering"
    Artist => "art"
  }
}

///|
pub fn refit_name(refit : @core.Refit) -> String {
  match refit {
    Baffles => "baffles"
    Plating => "plating"
    Injectors => "injectors"
    Coils => "coils"
  }
}

///|
/// A post as a control's label: sentence case, no article. The names above
/// are for use inside sentences.
pub fn post_label(post : @core.Post) -> String {
  match post {
    Drive => "Drive"
    Hull => "Hull"
    Craft => "Craft"
  }
}

///|
/// A craft as a control's label.
pub fn craft_label(craft : @core.Craft) -> String {
  match craft {
    Artist => "Art"
    Engineer => "Engineering"
  }
}

///|
/// A refit as a control's label.
pub fn refit_label(refit : @core.Refit) -> String {
  match refit {
    Baffles => "Baffles"
    Plating => "Plating"
    Injectors => "Injectors"
    Coils => "Coils"
  }
}

///|
pub fn phase_name(phase : @core.Phase) -> String {
  match phase {
    Burn => "burn"
    Coast => "coast"
    Approach => "approach"
    Arrived => "arrival"
  }
}

///|
pub fn hazard_name(h : @core.Hazard) -> String {
  match h {
    Breach => "A breach"
    Flare => "A flare"
    Salvage => "Salvage"
  }
}

///|
fn pct(n : Int64, of : Int64) -> Int64 {
  (n * 100L + of / 2L) / of
}

///|
/// Work units as whole crew-hours, "3 crew-hours", or "under a crew-hour".
pub fn crew_hours_words(units : Int64) -> String {
  let hours = units / (@core.HOUR * @core.CRAFT_UNIT)
  if hours <= 0L {
    "under a crew-hour"
  } else {
    plural(hours, "crew-hour", "crew-hours")
  }
}

///|
pub fn plural(n : Int64, one : String, many : String) -> String {
  if n == 1L {
    "1 \{one}"
  } else {
    "\{n} \{many}"
  }
}

///|
/// Where the ship is: the first thing the check-in says.
pub fn where_sentences(s : @core.State) -> Array[String] {
  match s.leg {
    InPort(since~) => {
      let next = @ships.itinerary[(s.ship.crossings %
        @ships.itinerary.length().to_int64()).to_int()]
      [
        "In port. Departs \{soon_words(since + @ships.PORT_STAY - s.at)} on a \{next.to_int()} light-year hop.",
        "Hull at \{pct(s.ship.hull, @core.HULL_FULL)}%.",
      ]
    }
    Underway(crossing=c, ..) => {
      let phase = match c.phase {
        Burn => "Burning toward the next port."
        Coast => "Coasting at the cap."
        Approach => "Burning to slow for port."
        Arrived => "Arrived. Docking."
      }
      let arrival = match c.forecast() {
        _ if c.phase == Arrived => []
        Some(at) =>
          ["Arriving \{in_words(at - c.t)}, if the drive stays as set."]
        None => ["Arrival is too far off to forecast."]
      }
      let on_drive = match c.count(Drive) {
        0L => "none"
        n => n.to_string()
      }
      let drive = if c.firing() {
        [
          "Drive at \{pct(c.setting(), @math.SETTING_FULL)}% of full burn, with \{on_drive} of the \{c.fit.needed} hands it needs.",
        ]
      } else {
        []
      }
      let hands = if c.hands.is_empty() {
        "Nobody is on a post yet."
      } else {
        "\{plural(c.count(Drive), "hand", "hands")} on the drive, \{c.count(Hull)} on the hull, \{c.count(Craft)} at crafts."
      }
      [
        phase,
        ..arrival,
        "Hull at \{pct(c.hull, @core.HULL_FULL)}%.",
        ..drive,
        hands,
        ..if c.phase == Arrived {
          []
        } else {
          ask_sentence(c)
        },
        ..c.demands.filter(d => d.status == Open).map(demand_sentence),
      ]
    }
  }
}

///|
pub fn ask_sentence(c : @core.Crossing) -> Array[String] {
  match c.ask {
    Some(post) => ["The ship asks for hands on \{post_name(post)}."]
    None => []
  }
}

///|
fn demand_sentence(d : @core.Demand) -> String {
  let hours = (d.need / @core.HAND + 1800L) / 3600L
  let done = pct(d.done, d.need)
  let by = if d.hazard == Salvage {
    "before the coast ends"
  } else {
    "before the \{phase_name(d.phase)} ends"
  }
  "\{hazard_name(d.hazard)} needs \{hours} crew-hours on \{post_name(d.hazard.post())} \{by}: \{done}% done."
}

///|
/// Where `crew` stands, in the second person.
pub fn you_sentences(s : @core.State, crew : String) -> Array[String] {
  guard s.crossing() is Some(c) else {
    ["You join the crew when the ship departs."]
  }
  guard c.hands.get(crew) is Some(h) else {
    ["You are not aboard this crossing. Take a post to join."]
  }
  let on = match h.post {
    Craft => "You are at your craft, \{craft_name(h.craft)}"
    p => "You are on \{post_name(p)}"
  }
  let watch = match h.watch {
    Some(w) => ", on watch for \{about(w.until - c.t)} more"
    None => ""
  }
  let order = match h.order {
    Some(o) =>
      [
        "Standing order: \{post_name(o.post)} when the \{phase_name(o.phase)} begins.",
      ]
    None => []
  }
  let craft = if h.post == Craft {
    []
  } else {
    ["Your craft is \{craft_name(h.craft)}."]
  }
  ["\{on}\{watch}.", ..craft, ..order]
}

///|
/// How a happening reaches a player as it happens. See docs/accessibility.md.
pub(all) enum Priority {
  /// Needs attention now. Rare.
  Interrupt
  /// Spoken when the screen reader is idle.
  Announce
  /// Kept in the log, not spoken.
  Quiet
} derive(Debug, Eq, Compare)

///|
/// `e`'s priority for the player `you`. A ship's line takes the priority of
/// the happening it answers, found in `story`.
pub fn priority(
  e : @core.Entry,
  you~ : String,
  story~ : Array[@core.Entry],
) -> Priority {
  match e.happening {
    Opened(_) => Interrupt
    Departed | Began(_) | Docked(_) | Met(_) | Missed(_) | Landed(..) =>
      Announce
    Stood(crew~) | Finished(crew~) | Made(crew~, ..) =>
      if crew == you {
        Announce
      } else {
        Quiet
      }
    Asked(_) | Took(..) | Left(_) => Quiet
    Promoted(..) => Announce
    Spoke(about~, ..) =>
      match story.iter().find_first(x => x.seq == about) {
        Some(x) if x.happening is Opened(_) => Interrupt
        _ => Announce
      }
  }
}

///|
/// A happening as a sentence for the player `you`, aboard the ship called
/// `ship` in English.
pub fn told(h : @core.Happening, you~ : String, ship~ : String) -> String {
  let who = (crew : String) => if crew == you { "You" } else { "A hand" }
  match h {
    Departed => "The ship left port."
    Began(phase=Arrived) => "The ship arrived."
    Began(phase~) => "The \{phase_name(phase)} began."
    Docked(recruits=0) => "The ship docked."
    Docked(recruits~) =>
      "The ship docked, and \{plural(recruits, "recruit", "recruits")} joined."
    Opened(hazard~) =>
      "\{hazard_name(hazard)} opened on \{post_name(hazard.post())}."
    Met(hazard~) => "\{hazard_name(hazard)} was met."
    Missed(hazard~) => "\{hazard_name(hazard)} was missed."
    Landed(refit~, level~) =>
      "A refit landed: \{refit_name(refit)} to level \{level}, \{refit_effect(refit, level)}."
    Asked(post=Some(post)) => "The ship asks for hands on \{post_name(post)}."
    Asked(post=None) => "The ship stopped asking for hands."
    Took(crew~, post=Craft) => "\{who(crew)} went to crafts."
    Took(crew~, post~) => "\{who(crew)} took \{post_name(post)}."
    Left(crew~) => "\{who(crew)} left the crew."
    Stood(crew~) =>
      if crew == you {
        "You stood your watch to its end."
      } else {
        "A hand stood a watch to its end."
      }
    Finished(crew~) => "\{who(crew)} finished a work."
    Made(crew~, units~, percent~) =>
      "\{who(crew)} made \{crew_hours_words(units)} of work at \{percent}%."
    Promoted(crew~, rank~, ..) =>
      "\{who(crew)} \{if crew == you { "were" } else { "was" }} promoted to \{rank_name(rank)}."
    Spoke(line~, ..) => "\{ship}: \{line}"
  }
}

///|
/// How long ago something `seconds` back happened: minutes to the nearest
/// 5 under an hour, then in the words of `about`.
pub fn ago(seconds : Int64) -> String {
  if seconds < 60L {
    "just now"
  } else if seconds < 3600L {
    let fives = ((seconds + 150L) / 300L * 5L).max(1L)
    "\{plural(fives, "minute", "minutes")} ago"
  } else {
    "\{about(seconds)} ago"
  }
}
