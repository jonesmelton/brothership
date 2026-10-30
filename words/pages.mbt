// The check-in's three pages, what each page's log holds, and the
// sentences that make accrual and consequence audible: rates beside
// stocks, what a choice changed, and what a player earned while away.

///|
/// A page of the check-in, each with its own log.
pub(all) enum Page {
  /// The player's post, watch, order and craft, and what they earn.
  You
  /// Phase, arrival, drive and demands.
  Voyage
  /// Hull, fit, refits, recruits and the ship's own words.
  Ship
} derive(Debug, Eq, Compare)

///|
/// A tally of zero, for a crew member with no hours this crossing.
fn zero_tally() -> @core.Tally {
  {
    drive: 0,
    hull: 0,
    craft: 0,
    regard: 0,
    work: 0,
    watches_stood: 0,
    watches_broken: 0,
    served: 0,
  }
}

///|
/// A record of zero, for a crew member the ship has never carried.
fn zero_record() -> @core.Record {
  { regard: 0, works: 0, carry: 0, rank: None, served: 0, }
}

///|
/// A hazard at the start of a sentence: "Breach", not "A breach".
fn hazard_title(h : @core.Hazard) -> String {
  match h {
    Breach => "Breach"
    Flare => "Flare"
    Dust => "Dust"
  }
}

///|
fn int_abs(x : Int64) -> Int64 {
  if x < 0L {
    -x
  } else {
    x
  }
}

///|
fn int_sign(x : Int64) -> Int32 {
  if x < 0L {
    -1
  } else if x > 0L {
    1
  } else {
    0
  }
}

///|
/// `tenths` as a number with at most one decimal place: 25 becomes "2.5".
fn tenths_words(tenths : Int64) -> String {
  if tenths % 10L == 0L {
    (tenths / 10L).to_string()
  } else {
    "\{tenths / 10L}.\{tenths % 10L}"
  }
}

///|
/// Regard per hour as the hours of regard it earns in an hour, to one
/// decimal place at most: "2.5".
fn regard_rate_words(per_hour : Int64) -> String {
  let tenths = per_hour * 10L / @core.REGARD_HOUR
  if tenths < 10L {
    "0.\{tenths}"
  } else {
    tenths_words(tenths)
  }
}

///|
/// An amount of regard as whole hours: "6 hours of regard", or "under an
/// hour of regard".
fn regard_words(regard : Int64) -> String {
  let hours = regard / @core.REGARD_HOUR
  if hours < 1L {
    "under an hour of regard"
  } else {
    "\{plural(hours, "hour", "hours")} of regard"
  }
}

///|
/// A span under an hour in minutes to the nearest 5, then in the words of
/// `about`.
fn coarse_span(seconds : Int64) -> String {
  if seconds < 3600L {
    let minutes = (seconds + 150L) / 300L * 5L
    if minutes < 5L {
      "under 5 minutes"
    } else {
      "about \{minutes} minutes"
    }
  } else {
    about(seconds)
  }
}

///|
/// The page's name as the navigation and headings say it.
pub fn Page::name(self : Page) -> String {
  match self {
    You => "You"
    Voyage => "Voyage"
    Ship => "Ship"
  }
}

///|
/// The page whose log holds `e`. Every happening has exactly one. A line
/// the ship spoke goes with the entry it is about, found in `story`, or to
/// `Ship` when that entry is not there.
pub fn page_of(
  e : @core.Entry,
  you~ : String,
  story~ : Array[@core.Entry],
) -> Page {
  page_of_entry(e, you~, story~, 0)
}

///|
fn page_of_entry(
  e : @core.Entry,
  you~ : String,
  story~ : Array[@core.Entry],
  depth : Int32,
) -> Page {
  match e.happening {
    Departed
    | Began(_)
    | Docked(..)
    | Opened(_)
    | Met(_)
    | Missed(_)
    | Cruised(_) => Voyage
    Landed(..) | Asked(_) => Ship
    Promoted(crew~, ..) => if crew == you { You } else { Ship }
    Signed(crew~)
    | Discharged(crew~)
    | Took(crew~, ..)
    | Left(crew~)
    | Stood(crew~)
    | Finished(crew~)
    | Made(crew~, ..) => if crew == you { You } else { Ship }
    Spoke(about~, ..) =>
      if depth >= 8 {
        Ship
      } else {
        match story.iter().find_first(x => x.seq == about) {
          Some(x) => page_of_entry(x, you~, story~, depth + 1)
          None => Ship
        }
      }
  }
}

///|
/// What a choice changed, at most two sentences, most important first:
/// arrival, then demands that now close differently, then the hull's
/// trend, then `you`'s regard per hour. `before` and `after` are the same
/// instant either side of one proposal. When nothing changed, one sentence
/// saying so and why, such as the coast not needing the drive.
pub fn effect(
  before : @core.State,
  after : @core.State,
  you~ : String,
) -> Array[String] {
  guard after.crossing() is Some(a) else { return [] }
  let b = before.crossing()
  let lines : Array[String] = []
  let made = match b {
    Some(bc) =>
      match (bc.hands.get(you), a.hands.get(you)) {
        (Some(x), Some(y)) if x.banked > 0L && y.banked == 0L => {
          let percent = @core.craft_percent(bc.ship.seed, you, bc.t)
          Some(
            "You made \{crew_hours_words(x.banked * percent / 100L)} of work at \{percent}%.",
          )
        }
        _ => None
      }
    None => None
  }
  let was_arrival = match b {
    Some(c) => c.forecast()
    None => None
  }
  match (was_arrival, a.forecast()) {
    (Some(was), Some(now)) =>
      if now != was && int_abs(now - was) >= 300L {
        let when = if now < was { "sooner" } else { "later" }
        lines.push("Arrival \{coarse_span(int_abs(now - was))} \{when}.")
      }
    (None, Some(now)) =>
      if b is Some(_) {
        lines.push("Arrival is \{in_words(now - a.t)}.")
      }
    (Some(_), None) => lines.push("Arrival is now too far off to forecast.")
    _ => ()
  }
  match b {
    Some(bc) => {
      // Both states are the same instant, so a demand changes only in how
      // it will close.
      match (bc.outcomes(), a.outcomes()) {
        (Some(was), Some(now)) =>
          for i, d in a.demands {
            guard d.status is (Waiting | Open) else { continue }
            guard was.get(i) is Some(w) && now.get(i) is Some(n) else {
              continue
            }
            match (w.status, n.status) {
              (Missed, Met) =>
                lines.push("\{hazard_title(d.hazard)} will now be met.")
              (Met, Missed) =>
                lines.push("\{hazard_title(d.hazard)} will now be missed.")
              _ => ()
            }
          }
        _ => ()
      }
      let was = bc.trend(you)
      let now = a.trend(you)
      if int_sign(was.hull) != int_sign(now.hull) {
        if now.hull > 0L {
          lines.push("The hull now mends.")
        } else if now.hull < 0L {
          lines.push("The hull now wears.")
        } else {
          lines.push("The hull holds steady.")
        }
      }
      if was.regard != now.regard {
        if now.regard <= 0L {
          lines.push("Your regard no longer grows.")
        } else {
          lines.push(
            "You now earn \{regard_rate_words(now.regard)} hours of regard an hour.",
          )
        }
      }
      if lines.is_empty() && made is None {
        lines.push("No change to arrival.")
      }
    }
    None => ()
  }
  if made is Some(line) {
    lines.insert(0, line)
  }
  if lines.length() > 2 {
    lines[0:2].to_owned()
  } else {
    lines
  }
}

///|
/// A player's running totals on one ship, kept by the client between
/// visits so a return can say what was earned. Each never falls, docking
/// included.
pub(all) struct Ledger {
  /// Unix seconds.
  at : Int64
  /// Regard on record plus this crossing's, in `Tally.regard` units.
  regard : Int64
  /// Works delivered plus works finished this crossing.
  works : Int64
  /// Crossings the ship has flown, plus one while underway.
  crossings : Int64
  /// The rank held. Absent in a ledger stored before ranks were held, which
  /// says nothing about promotion.
  rank : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Ledger::of(s : @core.State, you~ : String) -> Ledger {
  let record = s.ship.records.get(you).unwrap_or(zero_record())
  let tally = match s.crossing() {
    Some(c) => c.tallies.get(you).unwrap_or(zero_tally())
    None => zero_tally()
  }
  {
    at: s.at,
    regard: record.regard + tally.regard,
    works: record.works + (record.carry + tally.work) / @core.WORK_SIZE,
    crossings: s.ship.crossings +
    (if s.crossing() is Some(_) { 1L } else { 0L }),
    rank: Some(s.rank(you)),
  }
}

///|
/// What `you` earned between two ledgers, for the top of the You page:
/// regard, works, promotion. Empty when nothing changed.
pub fn since(before : Ledger, now : Ledger) -> Array[String] {
  let lines : Array[String] = []
  let regard = now.regard - before.regard
  if regard >= @core.REGARD_HOUR {
    lines.push("You earned \{regard_words(regard)}.")
  }
  let works = now.works - before.works
  if works == 1L {
    lines.push("You finished a work.")
  } else if works > 1L {
    lines.push("You finished \{works} works.")
  }
  if (before.rank, now.rank) is (Some(was), Some(reached)) && reached > was {
    lines.push("You were promoted to \{rank_name(reached)}.")
  }
  lines
}

///|
/// What `you` is earning now, with rates: regard this crossing and per
/// hour, with the ship's ask and an open demand's doubling named; progress
/// toward the next work for an artist; time served and the next promotion.
pub fn earning_sentences(s : @core.State, you~ : String) -> Array[String] {
  guard s.crossing() is Some(c) else { return [] }
  guard c.hands.get(you) is Some(h) else { return [] }
  let tally = c.tallies.get(you).unwrap_or(zero_tally())
  let record = s.ship.records.get(you).unwrap_or(zero_record())
  let lines : Array[String] = []
  let earned = if tally.regard > 0L {
    "\{capitalized(regard_words(tally.regard))} this crossing"
  } else {
    "No regard yet this crossing"
  }
  let rate = c.trend(you).regard
  if rate > 0L {
    lines.push("\{earned}, earning \{regard_rate_words(rate)} an hour.")
  } else {
    lines.push("\{earned}. This post earns none now.")
  }
  if c.ask == Some(h.post) {
    lines.push("Doubled: the ship asks for \{post_name(h.post)}.")
  }
  for d in c.demands {
    if d.status == Open && d.hazard.post() == h.post {
      lines.push(
        "Doubled: \{hazard_title(d.hazard)} needs \{post_name(h.post)}.",
      )
    }
  }
  if h.banked > 0L {
    lines.push(
      "Banked \{crew_hours_words(h.banked)} of \{craft_name(h.craft)}. Make it now for \{@core.MAKE_MIN}% to \{@core.MAKE_MAX}% of it.",
    )
  }
  if h.post == Craft && h.craft == Artist {
    let units = record.carry + tally.work
    let crew_hour = @core.HOUR * @core.CRAFT_UNIT
    let works = units / @core.WORK_SIZE
    lines.push(
      "Work \{record.works + works + 1L}: \{tenths_words(units % @core.WORK_SIZE * 10L / crew_hour)} of \{@core.WORK_SIZE / crew_hour} crew-hours made.",
    )
  }
  let served = c.served(you)
  lines.push(
    "Served \{plural(served / @core.HOUR, "hour", "hours")} aboard this ship.",
  )
  if h.rank >= @core.COMMANDER {
    lines.push("You hold the highest rank.")
  } else if @ships.eligible(c, you) {
    lines.push(
      "Promotion to \{rank_name(h.rank + 1L)} is the ship's to give, when it chooses.",
    )
  } else {
    let left = (@ships.ENSIGN_SERVICE - served + @core.HOUR - 1L) / @core.HOUR
    lines.push(
      "The ship can promote an ensign after \{@ships.ENSIGN_SERVICE / @core.HOUR} hours aboard: \{plural(left, "hour", "hours")} to go.",
    )
  }
  lines
}

///|
/// The tick at which `phase` ends, if the crossing reaches it in the
/// projection.
fn phase_end(c : @core.Crossing, phase : @core.Phase) -> Int64? {
  if phase < c.phase {
    return None
  }
  let mut cur = c
  for _ in 0..<4096 {
    if cur.phase == phase && cur.arrived_at is Some(at) {
      return Some(at)
    }
    if cur.phase > phase {
      return Some(cur.t)
    }
    let step = cur.next_boundary()
    guard step > 0L else { return None }
    let next = cur.apply(@core.Elapsed(ticks=step)) catch { _ => return None }
    if cur.phase == phase && next.phase != phase {
      return Some(cur.t + step)
    }
    cur = next
  }
  None
}

///|
/// How each open or waiting demand will close if nobody changes post:
/// "Breach will be met with about 40 minutes to spare." or "Breach will be
/// missed by about 2 crew-hours."
pub fn outlook_sentences(c : @core.Crossing) -> Array[String] {
  guard c.outcomes() is Some(outcomes) else { return [] }
  let lines : Array[String] = []
  for i, o in outcomes {
    guard c.demands.get(i) is Some(d) else { continue }
    guard d.status is (Waiting | Open) else { continue }
    match o.status {
      Met => {
        let line = match phase_end(c, d.phase) {
          Some(end) if end >= o.at =>
            "\{hazard_title(d.hazard)} will be met with \{coarse_span(end - o.at)} to spare."
          _ => "\{hazard_title(d.hazard)} will be met."
        }
        lines.push(line)
      }
      Missed => {
        let hours = (o.short + 7200L) / 14400L
        let by = if hours <= 0L {
          "under a crew-hour"
        } else if hours == 1L {
          "about a crew-hour"
        } else {
          "about \{hours} crew-hours"
        }
        lines.push("\{hazard_title(d.hazard)} will be missed by \{by}.")
      }
      Waiting | Open => ()
    }
  }
  lines
}

///|
/// Each refit's level and what it does, for the levels already built.
fn refit_level_sentences(fit : @core.Fit) -> Array[String] {
  let lines : Array[String] = []
  for refit in @core.refits {
    let level = fit.level(refit)
    if level > 0L {
      lines.push(
        "\{refit_label(refit)} at level \{level}: \{refit_effect(refit, level)}.",
      )
    }
  }
  lines
}

///|
/// The refit under way and its progress. Engineers add to it only when they
/// make their banked work.
fn refit_under_way(fit : @core.Fit) -> Array[String] {
  match fit.refit {
    None => []
    Some(refit) => {
      let level = fit.level(refit) + 1L
      let done = pct(fit.progress, fit.cost(refit))
      [
        "\{capitalized(refit_name(refit))} to level \{level}: \{done}% built. Engineers add to it when they make their banked work.",
      ]
    }
  }
}

///|
/// Who the ship has recruited, and how near the next one is.
fn recruit_sentences(ship : @core.Ship) -> Array[String] {
  if ship.recruits >= @core.MAX_RECRUITS {
    ["Recruits: \{ship.recruits}, the most a ship carries."]
  } else {
    [
      "Recruits: \{ship.recruits} of \{@core.MAX_RECRUITS}.",
      "\{ship.toward_recruit} of \{@core.WORKS_PER_RECRUIT} works toward the next recruit.",
    ]
  }
}

///|
/// The ship page: the hull with its trend, each refit's level and effect,
/// the refit under way with its progress and rate, recruits, and works
/// toward the next recruit.
pub fn ship_sentences(s : @core.State) -> Array[String] {
  let lines : Array[String] = []
  match s.crossing() {
    Some(c) => {
      let trend = c.trend("")
      let rate = trend.hull * 1000L / @core.HULL_FULL
      let hull = pct(c.hull, @core.HULL_FULL)
      if rate < 0L {
        lines.push(
          "Hull at \{hull}%, wearing about \{tenths_words(-rate)}% an hour.",
        )
      } else if rate > 0L && hull < 100L {
        lines.push(
          "Hull at \{hull}%, mending about \{tenths_words(rate)}% an hour.",
        )
      } else {
        lines.push("Hull at \{hull}%.")
      }
      for line in refit_level_sentences(c.fit) {
        lines.push(line)
      }
      for line in refit_under_way(c.fit) {
        lines.push(line)
      }
      for line in recruit_sentences(s.ship) {
        lines.push(line)
      }
    }
    None => {
      lines.push("Hull at \{pct(s.ship.hull, @core.HULL_FULL)}%.")
      for line in refit_level_sentences(s.ship.fit) {
        lines.push(line)
      }
      for line in refit_under_way(s.ship.fit) {
        lines.push(line)
      }
      for line in recruit_sentences(s.ship) {
        lines.push(line)
      }
    }
  }
  lines
}

///|
fn int_pow(base : Int64, level : Int64) -> Int64 {
  let mut n = 1L
  for _ in 0..<level.to_int() {
    n = n * base
  }
  n
}

///|
/// What `level` of `refit` does, for the ship page and a landed refit:
/// "hull wears 44% less".
pub fn refit_effect(refit : @core.Refit, level : Int64) -> String {
  if level <= 0L {
    return "not fitted"
  }
  match refit {
    Baffles => {
      let den = int_pow(4L, level)
      let kept = (100L * int_pow(3L, level) + den / 2L) / den
      "hull wears \{100L - kept}% less"
    }
    Plating => {
      let den = int_pow(4L, level)
      let got = (100L * int_pow(5L, level) + den / 2L) / den
      "hull hands mend \{got - 100L}% more"
    }
    Injectors =>
      "\{level} fewer \{if level == 1L { "drive hand" } else { "drive hands" }} for full burn"
    Coils => {
      let den = int_pow(5L, level)
      let got = (100L * int_pow(6L, level) + den / 2L) / den
      let higher = if got - 100L == 20L { "a fifth" } else { "\{got - 100L}%" }
      "the γ cap \{higher} higher, from the next departure"
    }
  }
}

///|
/// `s` with its first letter in capitals.
fn capitalized(s : String) -> String {
  match s.get_char(0) {
    Some(c) if c >= 'a' && c <= 'z' =>
      (c.to_int() - 32).unsafe_to_char().to_string() +
      s.view(start_offset=1).to_owned()
    _ => s
  }
}
