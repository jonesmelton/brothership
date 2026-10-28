// The check-in as sentences. Every fact on the screen is one of these first;
// the layout only arranges them. See docs/accessibility.md.

///|
/// A span in words that coarsen with length and do not tick: under an
/// hour, about an hour, whole hours to 6, the nearest 3 hours to 36, then
/// whole days. See research/liveship-travel-math.md, section 11.
fn about(seconds : Int64) -> String {
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
fn in_words(seconds : Int64) -> String {
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
fn post_name(post : @core.Post) -> String {
  match post {
    Drive => "the drive"
    Hull => "the hull"
    Craft => "crafts"
  }
}

///|
fn craft_name(craft : @core.Craft) -> String {
  match craft {
    Engineer => "engineering"
    Artist => "art"
  }
}

///|
fn refit_name(refit : @core.Refit) -> String {
  match refit {
    Baffles => "baffles"
    Plating => "plating"
    Injectors => "injectors"
    Coils => "coils"
  }
}

///|
fn phase_name(phase : @core.Phase) -> String {
  match phase {
    Burn => "burn"
    Coast => "coast"
    Approach => "approach"
    Arrived => "arrival"
  }
}

///|
fn hazard_name(h : @core.Hazard) -> String {
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
fn plural(n : Int64, one : String, many : String) -> String {
  if n == 1L {
    "1 \{one}"
  } else {
    "\{n} \{many}"
  }
}

///|
/// Where the ship is: the first thing the check-in says.
fn where_sentences(s : @core.State) -> Array[String] {
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
      let drive = if c.firing() {
        [
          "Drive at \{pct(c.setting(), @math.SETTING_FULL)}% of full burn, with \{c.count(Drive)} of \{c.fit.needed} hands it needs.",
        ]
      } else {
        []
      }
      [
        phase,
        ..arrival,
        "Hull at \{pct(c.hull, @core.HULL_FULL)}%.",
        ..drive,
        "\{plural(c.count(Drive), "hand", "hands")} on the drive, \{c.count(Hull)} on the hull, \{c.count(Craft)} at crafts.",
        ..ask_sentence(c),
        ..c.demands.filter(d => d.status == Open).map(demand_sentence),
      ]
    }
  }
}

///|
fn ask_sentence(c : @core.Crossing) -> Array[String] {
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
fn you_sentences(s : @core.State, crew : String) -> Array[String] {
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
/// What changed between `was`, the state at the player's last visit, and
/// `now`: crossings flown, phases, demands, refits, and the player's own
/// watches and works.
fn news(was : @core.State, now : @core.State, crew : String) -> Array[String] {
  let out = []
  let flown = now.ship.crossings - was.ship.crossings
  if flown > 0L {
    out.push("The ship reached port \{plural(flown, "time", "times")}.")
  }
  match (was.crossing(), now.crossing()) {
    (Some(a), Some(b)) if flown == 0L => {
      if a.phase != b.phase {
        out.push("The \{phase_name(b.phase)} began.")
      }
      for i, d in b.demands {
        let before = a.demands.get(i).map(x => x.status)
        guard before != Some(d.status) else { continue }
        let what = hazard_name(d.hazard)
        match d.status {
          Open => out.push("\{what} opened on \{post_name(d.hazard.post())}.")
          Met => out.push("\{what} was met.")
          Missed => out.push("\{what} was missed.")
          Waiting => ()
        }
      }
      for r in @core.refits {
        if b.fit.level(r) > a.fit.level(r) {
          out.push(
            "A refit landed: \{refit_name(r)} to level \{b.fit.level(r)}.",
          )
        }
      }
      match (a.tallies.get(crew), b.tallies.get(crew)) {
        (Some(x), Some(y)) => {
          if y.watches_stood > x.watches_stood {
            out.push("You stood your watch to its end.")
          }
          if y.work / @core.WORK_SIZE > x.work / @core.WORK_SIZE {
            out.push("You finished a work.")
          }
        }
        _ => ()
      }
    }
    (_, Some(_)) => out.push("The ship left port.")
    _ => ()
  }
  out
}
