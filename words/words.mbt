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
pub fn soon_words(seconds : Int64) -> String {
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
/// Where a ship in the list is, at `now` in Unix seconds, without saying who
/// is aboard.
pub fn whereabouts_sentence(l : @core.Listing, now~ : Int64) -> String {
  let from = l.from
  // Underway, a listing always names where the ship is bound.
  let to = l.bound.unwrap_or("its next world")
  match (l.whereabouts, l.bound) {
    (InPort(departs~), Some(to)) =>
      "In port at \{from}, leaving for \{to} \{soon_words(departs - now)}."
    (InPort(departs~), None) =>
      "In port at \{from}, leaving \{soon_words(departs - now)} for a world it has not chosen yet."
    (Underway(arrives=Some(at)), _) if at <= now => "Arrived at \{to}, docking."
    (Underway(arrives=Some(at)), _) =>
      "Between \{from} and \{to}, arriving \{in_words(at - now)}."
    (Underway(arrives=None), _) => "Between \{from} and \{to}."
  }
}

///|
/// A ship in the list to choose from, at `now` in Unix seconds: where it is
/// and who is aboard.
pub fn listing_sentence(l : @core.Listing, now~ : Int64) -> String {
  let aboard = match l.officers {
    0L => "Nobody aboard yet."
    n => "\{plural(n, "officer", "officers")} aboard."
  }
  "\{whereabouts_sentence(l, now~)} \{aboard}"
}

///|
/// A ship in the fleet, at `now`, with its title and no one's business but
/// where it is.
pub fn fleet_sentence(l : @core.Listing, now~ : Int64) -> String {
  "\{l.name}: \{whereabouts_sentence(l, now~)}"
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
    Dust => "Dust"
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
/// Where the ship underway is bound.
fn destination(s : @core.State) -> @ships.World {
  guard @ships.bound_for(s) is Some(w) else { abort("the ship is in port") }
  w
}

///|
/// Where the ship is: the first thing the check-in says.
pub fn where_sentences(s : @core.State) -> Array[String] {
  match s.leg {
    InPort(_) => {
      let at = @ships.origin(s.ship)
      let l = s.launch().unwrap()
      let hull = pct(s.ship.hull, @core.HULL_FULL)
      let then = pct(l.hull, @core.HULL_FULL)
      let yard = if then == hull {
        "Hull at \{hull}%."
      } else {
        "The yard has the hull at \{hull}%, and \{then}% by then."
      }
      let bound = match @ships.bound_for(s) {
        Some(next) => {
          let hop = fixed(at.distance_to(next), 1)
          "In port at \{at.name}, bound for \{next.name}, \{hop} light-years away."
        }
        None =>
          "In port at \{at.name}. The ship has not chosen where it goes next."
      }
      [
        bound,
        "Stores load \{soon_words(l.ready_at - s.at)}, and the ship departs then.",
        yard,
      ]
    }
    Underway(crossing=c, ..) => {
      let to = destination(s).name
      let phase = match c.phase {
        Burn => "Burning toward \{to}."
        Coast => "Coasting toward \{to} at the cap."
        Approach => "Burning to slow for \{to}."
        Arrived => "Arrived at \{to}. Docking."
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
        ..reckoning_sentences(c, s),
        ..arrival,
        ..turn_sentence(c),
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
/// The Voyage page's opening readout, in the order of a shipping forecast:
/// phase, arrival, hull, drive. Empty in port, where `where_sentences`
/// already opens with the news.
pub fn readout(s : @core.State) -> String {
  guard s.crossing() is Some(c) else { "" }
  let to = destination(s).name
  let hull = "Hull \{pct(c.hull, @core.HULL_FULL)}%."
  guard c.phase != Arrived else { "Arrived at \{to}. Docking. \{hull}" }
  let phase = match c.phase {
    Burn => "Burn."
    Coast => "Coast."
    Approach | Arrived => "Approach."
  }
  let arrival = match c.forecast() {
    Some(at) => "\{to} \{in_words(at - c.t)}."
    None => "\{to} too far off to forecast."
  }
  let drive = if c.firing() {
    " Drive \{pct(c.setting(), @math.SETTING_FULL)}%, \{c.count(Drive)} of \{c.fit.needed} hands."
  } else {
    ""
  }
  "\{phase} \{arrival} \{hull}\{drive}"
}

///|
/// What `where_sentences` says that `readout` does not: the distance, the
/// turn, who is where and the open demands. In port, all of it.
pub fn where_rest(s : @core.State) -> Array[String] {
  guard s.crossing() is Some(c) else { return where_sentences(s) }
  guard c.phase != Arrived else { [] }
  let hands = if c.hands.is_empty() {
    "Nobody is on a post yet."
  } else {
    "\{plural(c.count(Drive), "hand", "hands")} on the drive, \{c.count(Hull)} on the hull, \{c.count(Craft)} at crafts."
  }
  [
    ..reckoning_sentences(c, s),
    ..turn_sentence(c),
    hands,
    ..c.demands.filter(d => d.status == Open).map(demand_sentence),
  ]
}

///|
/// What `crew` taking `post` would change, in a few words for a control's
/// label, found by applying the post to a copy of the crossing. Empty when
/// `crew` already holds the post, the crossing is over, or nothing changes.
pub fn post_effect(
  c : @core.Crossing,
  crew : String,
  post : @core.Post,
) -> String {
  guard c.phase != Arrived && c.hands.get(crew).map(h => h.post) != Some(post) else {
    ""
  }
  let after = try c.apply(Posted(crew~, post~)) catch {
    _ => return ""
  } noraise {
    after => after
  }
  match post {
    Drive =>
      match (c.forecast(), after.forecast()) {
        (Some(now), Some(then)) => {
          let gap = (now - then).abs()
          if gap < 1800L {
            "arrival about the same"
          } else if then < now {
            "arrive \{about(gap)} sooner"
          } else {
            "arrive \{about(gap)} later"
          }
        }
        _ => ""
      }
    Hull => {
      let was = c.trend(crew).hull
      let will = after.trend(crew).hull
      if will == was {
        "hull unchanged"
      } else if will >= 0L {
        if was < 0L {
          "hull stops wearing"
        } else {
          "hull mends faster"
        }
      } else if was >= 0L {
        "hull starts to wear"
      } else {
        let change = (was - will).abs() * 100L / was.abs()
        if will > was {
          "hull wear down \{change}%"
        } else {
          "hull wear up \{change}%"
        }
      }
    }
    Craft => {
      let banked = (k : @core.Crossing) => {
        try k.apply(Elapsed(ticks=@core.HOUR)) catch {
          _ => 0L
        } noraise {
          next => next.hands.get(crew).map(h => h.banked).unwrap_or(0L)
        }
      }
      if banked(after) > banked(c) {
        "banks work for your craft"
      } else {
        ""
      }
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
/// What the ship asks for in port, and what it would do there.
pub fn port_ask_sentence(s : @core.State) -> Array[String] {
  guard s.leg is InPort(port~) else { [] }
  match port.ask {
    Some(Drive) => ["The ship asks for hands on the drive, to load stores."]
    Some(Hull) => ["The ship asks for hands on the hull, to work the yard."]
    Some(Craft) => ["The ship asks for hands at crafts."]
    None => []
  }
}

///|
/// A standing order as a sentence.
pub fn order_sentence(o : @core.Order) -> String {
  match o.phase {
    Arrived => "Standing order: \{post_name(o.post)} in port, from arrival."
    p =>
      "Standing order: \{post_name(o.post)} when the \{phase_name(p)} begins."
  }
}

///|
/// What taking `post` in port would do to the launch, for `crew`; nothing
/// for the post held.
pub fn port_effect(s : @core.State, crew : String, post : @core.Post) -> String {
  guard s.launch() is Some(now) &&
    s.officers.get(crew).bind(o => o.post) != Some(post) else {
    ""
  }
  let then = try s.apply(Crew(crew~, intent=Posted(post~))) catch {
    _ => return ""
  } noraise {
    after => after.launch().unwrap()
  }
  let gap = (now.ready_at - then.ready_at).abs()
  let when = if gap < 300L {
    "departs about the same"
  } else if then.ready_at < now.ready_at {
    "departs \{minutes_words(gap)} sooner"
  } else {
    "departs \{minutes_words(gap)} later"
  }
  match post {
    _ if then.ready_at != now.ready_at && post != Craft =>
      "\{when}, hull \{pct(then.hull, @core.HULL_FULL)}% then"
    Drive | Hull => "hull \{pct(then.hull, @core.HULL_FULL)}% at departure"
    Craft if then.ready_at != now.ready_at => "\{when}, nothing done in port"
    Craft => "nothing done in port"
  }
}

///|
/// A span to the nearest 5 minutes under an hour, then in the words of
/// `about`.
fn minutes_words(seconds : Int64) -> String {
  if seconds < 3600L {
    plural(((seconds + 150L) / 300L * 5L).max(5L), "minute", "minutes")
  } else {
    about(seconds)
  }
}

///|
fn demand_sentence(d : @core.Demand) -> String {
  let hours = (d.need / @core.HAND + 1800L) / 3600L
  let done = pct(d.done, d.need)
  let by = if d.hazard == Dust {
    "before the coast ends"
  } else {
    "before the \{phase_name(d.phase)} ends"
  }
  "\{hazard_name(d.hazard)} needs \{hours} crew-hours on \{post_name(d.hazard.post())} \{by}: \{done}% done."
}

///|
/// When `crew` may leave the ship, in the second person; nothing if not
/// aboard.
pub fn leaving_sentences(s : @core.State, crew : String) -> Array[String] {
  guard s.officers.get(crew) is Some(officer) else { [] }
  match (s.leg, officer.leaving) {
    (InPort(_), _) =>
      ["You may leave the ship before it departs, and choose another."]
    (Underway(_), true) =>
      [
        "You leave the ship when it docks at \{destination(s).name}, and choose another then.",
      ]
    (Underway(_), false) =>
      [
        "You are aboard until the ship docks at \{destination(s).name}, and may leave then.",
      ]
  }
}

///|
/// Where `crew` stands, in the second person.
pub fn you_sentences(s : @core.State, crew : String) -> Array[String] {
  guard s.officers.get(crew) is Some(officer) else { ["You are not aboard."] }
  guard s.crossing() is Some(c) else {
    match officer.post {
      Some(Drive) =>
        [
          "You load stores on the drive, and take the drive when the ship departs.",
        ]
      Some(Hull) =>
        [
          "You work the yard on the hull, and take the hull when the ship departs.",
        ]
      Some(Craft) =>
        [
          "Crafts do nothing in port. You go to your craft when the ship departs.",
        ]
      None =>
        [
          "You have no post. Choose one to work in port and take when the ship departs.",
        ]
    }
  }
  guard c.hands.get(crew) is Some(h) else {
    ["You are standing down. Take a post to work."]
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
    Some(o) => [order_sentence(o)]
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
    Departed
    | Began(_)
    | Docked(..)
    | Met(_)
    | Missed(_)
    | Landed(..)
    | Cruised(_)
    | Bound(_) => Announce
    // Your own making is announced by its effect sentence already.
    Made(_) => Quiet
    Stood(crew~) | Finished(crew~) | Discharged(crew~) =>
      if crew == you {
        Announce
      } else {
        Quiet
      }
    Asked(_) | Signed(_) | Took(..) | Left(_) | Loaded => Quiet
    // The roll call is read on the Voyage page; speech announces your own.
    Promoted(crew~, ..) => if crew == you { Announce } else { Quiet }
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
  told_by(h, you~, ship~, who=crew => if crew == you { "You" } else { "A hand" })
}

///|
/// A happening as a sentence, naming a crew member by `who`. The roster uses
/// this to name an officer by service number instead of "A hand".
pub fn told_by(
  h : @core.Happening,
  you~ : String,
  ship~ : String,
  who~ : (String) -> String,
) -> String {
  match h {
    Departed => "The ship left port."
    Began(phase=Arrived) => "The ship arrived."
    Began(phase~) => "The \{phase_name(phase)} began."
    Docked(recruits=0, ..) => "The ship docked."
    Docked(recruits~, ..) =>
      "The ship docked, and \{plural(recruits, "recruit", "recruits")} joined."
    Opened(hazard~) =>
      "\{hazard_name(hazard)} opened on \{post_name(hazard.post())}."
    Met(hazard~) => "\{hazard_name(hazard)} was met."
    Missed(hazard~) => "\{hazard_name(hazard)} was missed."
    Landed(refit~, level~) =>
      "A refit landed: \{refit_name(refit)} to level \{level}, \{refit_effect(refit, level)}."
    Loaded => "The stores are loaded."
    Asked(post=Some(post)) => "The ship asks for hands on \{post_name(post)}."
    Asked(post=None) => "The ship stopped asking for hands."
    Took(crew~, post=Craft) => "\{who(crew)} went to crafts."
    Took(crew~, post~) => "\{who(crew)} took \{post_name(post)}."
    Signed(crew~) => "\{who(crew)} signed on."
    Discharged(crew~) => "\{who(crew)} left the ship."
    Left(crew~) => "\{who(crew)} stood down."
    Stood(crew~) =>
      if crew == you {
        "You stood your watch to its end."
      } else {
        "\{who(crew)} stood a watch to its end."
      }
    Finished(crew~) => "\{who(crew)} finished a work."
    Made(crew~, craft~, units~, percent~) =>
      "\{who(crew)} made \{crew_hours_words(units)} of \{craft_name(craft)} at \{percent}%."
    Promoted(crew~, rank~, ..) =>
      "\{who(crew)} \{if crew == you { "were" } else { "was" }} promoted to \{rank_name(rank)}."
    Spoke(line~, ..) => "\{ship}: \{line}"
    Cruised(cruise~) => "The ship will coast at \{cruise_words(cruise)}."
    Bound(world~) =>
      match @ships.world_named(world) {
        Some(w) => "The ship has chosen to leave for \{w.name}, at \{w.star}."
        None => "The ship has chosen to leave for \{world}."
      }
  }
}

///|
/// A cruise, in thousandths of the γ cap, as a share of it.
pub fn cruise_words(cruise : Int64) -> String {
  match cruise {
    1000L => "its full γ cap"
    800L => "four fifths of its γ cap"
    600L => "three fifths of its γ cap"
    _ => "\{pct(cruise, 1000L)}% of its γ cap"
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
