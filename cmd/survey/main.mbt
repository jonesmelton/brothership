// Prints the crossing survey as plain text: every ship's envelope, every
// scenario's batch, the same crew on each ship, one player under each
// policy, and multi-crossing voyages with docking between legs.
//
//   moon run cmd/survey --target native -- [section] [runs]
//
// Sections: envelopes, scenarios, ships, policies, voyages, careers, story,
// all.

///|
fn hours(ticks : Int64) -> String {
  let tenths = (ticks * 10L + 1800L) / 3600L
  "\{tenths / 10L}.\{tenths % 10L}"
}

///|
fn pct(n : Int64, d : Int64) -> String {
  guard d > 0L else { "-" }
  "\{(n * 100L + d / 2L) / d}%"
}

///|
fn pad(s : String, n : Int32) -> String {
  if s.length() >= n {
    s
  } else {
    s + " ".repeat(n - s.length())
  }
}

///|
fn row(cells : Array[(String, Int32)]) -> Unit {
  println(cells.map(c => pad(c.0, c.1)).join(" "))
}

///|
let distances : Array[Double] = [3.0, 5.0, 8.0, 12.0, 20.0, 30.0, 45.0, 60.0]

///|
fn envelopes() -> Unit {
  println("== envelopes: fastest–slowest hours, spread")
  row([("ship", 32)] + distances.map(d => ("\{d.to_int()} ly", 15)))
  for p in @ships.profiles() {
    let cells = distances.map(d => {
      let plan = { ..p.route, distance_ly: d, }.plan()
      let spread = plan.slowest() * 100L / plan.fastest()
      (
        "\{hours(plan.fastest())}–\{hours(plan.slowest())} \{spread / 100L}.\{spread % 100L / 10L}",
        15,
      )
    })
    row([(p.name, 32)] + cells)
  }
  println("")
}

///|
struct Summary {
  arrival : Array[Int64]
  min_hull : Array[Int64]
  met : Int64
  missed : Int64
  levels : Int64
  works : Int64
  regard : Int64
  players : Int64
  checkins : Int64
  dead : Int64
  live : Int64
  newsy : Int64
  watches : Int64
  broken : Int64
  runs : Int64
}

///|
fn summarize(s : @sim.Scenario, runs : Int32) -> Summary {
  let arrival = []
  let min_hull = []
  let mut met = 0L
  let mut missed = 0L
  let mut levels = 0L
  let mut works = 0L
  let mut regard = 0L
  let mut checkins = 0L
  let mut dead = 0L
  let mut live = 0L
  let mut newsy = 0L
  let mut watches = 0L
  let mut broken = 0L
  let players = s.actors.filter(a => a.is_player()).length().to_int64()
  for i in 0..<runs {
    let r = s.run(i.to_int64() + 1L)
    arrival.push(r.arrived_at)
    min_hull.push(r.min_hull)
    for d in r.last.demands {
      if d.status == Met {
        met += 1L
      } else if d.status == Missed {
        missed += 1L
      }
    }
    let f = r.last.fit
    levels += f.baffles + f.plating + f.injectors
    for crew, t in r.last.tallies {
      works += t.work
      if s.actor_of(crew) is Some(a) && a.is_player() {
        regard += t.regard
        watches += t.watches_stood
        broken += t.watches_broken
      }
    }
    checkins += r.checkins.to_int64()
    dead += r.dead_checkins.to_int64()
    live += r.live_checkins.to_int64()
    newsy += r.newsy_checkins.to_int64()
  }
  {
    arrival,
    min_hull,
    met,
    missed,
    levels,
    works,
    regard,
    players,
    checkins,
    dead,
    live,
    newsy,
    watches,
    broken,
    runs: runs.to_int64(),
  }
}

///|
let header : Array[(String, Int32)] = [
  ("", 34),
  ("p10–p50–p90 h", 17),
  ("env h", 11),
  ("hull", 5),
  ("met/miss", 9),
  ("refit", 6),
  ("works", 6),
  ("regard", 7),
  ("live", 5),
  ("dead", 5),
  ("news", 5),
  ("watch", 9),
]

///|
fn summary_row(name : String, s : @sim.Scenario, m : Summary) -> Unit {
  let plan = s.route.plan()
  let n = m.runs
  let per = (x : Int64) => "\{x * 10L / n / 10L}.\{x * 10L / n % 10L}"
  row([
    (name, 34),
    (
      "\{hours(@sim.percentile(m.arrival, 10))}–\{hours(@sim.percentile(m.arrival, 50))}–\{hours(@sim.percentile(m.arrival, 90))}",
      17,
    ),
    ("\{hours(plan.fastest())}–\{hours(plan.slowest())}", 11),
    (pct(@sim.percentile(m.min_hull, 50), @core.HULL_FULL), 5),
    ("\{per(m.met)}/\{per(m.missed)}", 9),
    (per(m.levels), 6),
    (per(m.works * 10L / @core.WORK_SIZE).to_string(), 6),
    (
      if m.players > 0L {
        (m.regard / n / m.players / @core.REGARD_HOUR).to_string()
      } else {
        "-"
      },
      7,
    ),
    (pct(m.live, m.checkins), 5),
    (pct(m.dead, m.checkins), 5),
    (pct(m.newsy, m.checkins), 5),
    ("\{per(m.watches)}/\{per(m.broken)}", 9),
  ])
}

///|
fn legend() -> Unit {
  println(
    "hull: median lowest. met/miss, refit (levels landed), watch (stood/broken by players): per run. works: tenths of a work per run, all crew. regard: hours per player per run. live: player check-ins with two or more undominated choices. dead: could not move arrival 5 min. news: came back to something new.",
  )
  println("")
}

///|
fn scenarios(runs : Int32) -> Unit {
  println("== scenarios, \{runs} seeds each")
  row(header)
  for s in @sim.scenarios() {
    summary_row(s.name, s, summarize(s, runs))
  }
  legend()
}

///|
fn ships(runs : Int32) -> Unit {
  for base in [@sim.scenarios()[0], @sim.scenarios()[1]] {
    println("== \{base.name}, on each ship, 20 ly")
    row(header)
    for p in @ships.profiles() {
      let s = { ..base, ship: p, route: p.route, }
      summary_row(p.name, s, summarize(s, runs))
    }
    println("")
  }
}

///|
fn policies(runs : Int32) -> Unit {
  let base = @sim.scenarios()[0]
  for craft in [@core.Artist, @core.Engineer] {
    println(
      "== solo player as \{craft_name(craft)} with NPC crew, by the player's policy",
    )
    row(header)
    for policy in @sim.policies {
      let actors = base.actors.copy()
      actors[0] = { ..actors[0], policy, craft, }
      let s = { ..base, actors, }
      let m = summarize(s, runs)
      let mut own = 0L
      for i in 0..<runs {
        own += s.run(i.to_int64() + 1L).last.tallies
          .get(@sim.actor_id(0))
          .unwrap().work
      }
      summary_row(
        "\{policy.name()} (own works \{own * 10L / runs.to_int64() / @core.WORK_SIZE})",
        s,
        m,
      )
    }
    println("")
  }
}

///|
fn voyages() -> Unit {
  let legs : Array[Double] = [8.0, 20.0, 12.0, 30.0, 20.0, 8.0]
  let crew = @sim.scenarios()[0].actors
  for p in @ships.profiles() {
    println("== voyage on \{p.name}: solo thoughtful player, two NPCs")
    let actors = crew.copy()
    actors[0] = { ..actors[0], policy: Thoughtful, }
    let s : @sim.Scenario = {
      name: "voyage",
      ship: p,
      route: p.route,
      hull: @core.HULL_FULL,
      actors,
    }
    row([
      ("leg", 8),
      ("hours", 7),
      ("env", 11),
      ("hull→", 7),
      ("demands", 16),
      ("needed/wear/repair", 22),
      ("works", 6),
      ("recruits", 9),
      ("rank", 5),
      ("promoted", 9),
      ("live", 5),
    ])
    let voyage = s.voyage(legs, 11L)
    for leg in voyage {
      let r = leg.run
      let f = r.last.fit
      let ds = r.last.demands
        .map(d => {
          "\{hazard_name(d.hazard)} \{if d.status == Met { "met" } else { "missed" }}"
        })
        .join(", ")
      let delivered = leg.docked.records
        .values()
        .fold(init=0L, (n, x) => n + x.works)
      row([
        ("\{leg.distance_ly.to_int()} ly", 8),
        (hours(r.arrived_at), 7),
        ("\{hours(r.plan.fastest())}–\{hours(r.plan.slowest())}", 11),
        (pct(leg.docked.hull, @core.HULL_FULL), 7),
        (ds, 16),
        ("\{f.needed}/\{f.wear}/\{f.repair}", 22),
        (delivered.to_string(), 6),
        (leg.docked.recruits.to_string(), 9),
        (leg.docked.rank(@sim.actor_id(0)).to_string(), 5),
        (leg.promotions.length().to_string(), 9),
        (pct(r.live_checkins.to_int64(), r.checkins.to_int64()), 5),
      ])
    }
    let last = voyage[voyage.length() - 1].docked
    let counts = Array::make(@core.COMMANDER.to_int() + 1, 0)
    for crew in last.records.keys() {
      if s.actor_of(crew).map(a => a.is_player()).unwrap_or(false) {
        counts[last.rank(crew).to_int()] += 1
      }
    }
    println(
      "players by rank 0..\{@core.COMMANDER}: \{counts.map(n => n.to_string()).join(" ")}, promotions: \{voyage.fold(init=0, (n, l) => n + l.promotions.length())}",
    )
    println("")
  }
}

///|
fn craft_name(c : @core.Craft) -> String {
  match c {
    Engineer => "engineer"
    Artist => "artist"
  }
}

///|
fn hazard_name(h : @core.Hazard) -> String {
  match h {
    Breach => "breach"
    Flare => "flare"
    Salvage => "salvage"
  }
}

///|
/// The same six-leg voyage under each choice of the solo player's policy
/// and craft: what one player's habits add up to across ports.
fn careers(runs : Int32) -> Unit {
  let legs : Array[Double] = [8.0, 20.0, 12.0, 30.0, 20.0, 8.0]
  let crew = @sim.scenarios()[0].actors
  for p in [@ships.profiles()[0], @ships.profiles()[3]] {
    println(
      "== six-leg voyage on \{p.name}, solo player with two NPCs, \{runs} seeds",
    )
    row([
      ("player", 26),
      ("total h", 8),
      ("own works", 10),
      ("recruits", 9),
      ("refits", 7),
      ("rank", 5),
      ("lowest hull", 12),
    ])
    for craft in [@core.Artist, @core.Engineer] {
      for
        policy in [
          @sim.Selfish,
          @sim.Cooperative,
          @sim.Dutiful,
          @sim.Thoughtful,
          @sim.Driver,
        ] {
        let actors = crew.copy()
        actors[0] = { ..actors[0], policy, craft, }
        let s : @sim.Scenario = {
          name: "career",
          ship: p,
          route: p.route,
          hull: @core.HULL_FULL,
          actors,
        }
        let mut total = 0L
        let mut works = 0L
        let mut recruits = 0L
        let mut refits = 0L
        let mut rank = 0L
        let mut low = @core.HULL_FULL
        for seed in 0..<runs {
          let voyage = s.voyage(legs, seed.to_int64() + 1L)
          let end = voyage[voyage.length() - 1].docked
          for leg in voyage {
            total += leg.run.arrived_at
            low = low.min(leg.run.min_hull)
          }
          works += end.records
            .get(@sim.actor_id(0))
            .map(r => r.works)
            .unwrap_or(0L)
          recruits += end.recruits
          refits += end.fit.baffles +
            end.fit.plating +
            end.fit.injectors +
            end.fit.coils
          rank += end.rank(@sim.actor_id(0))
        }
        let n = runs.to_int64()
        let tenths = (x : Int64) => "\{x * 10L / n / 10L}.\{x * 10L / n % 10L}"
        row([
          ("\{policy.name()} \{craft_name(craft)}", 26),
          (hours(total / n), 8),
          (tenths(works), 10),
          (tenths(recruits), 9),
          (tenths(refits), 7),
          (tenths(rank), 5),
          (pct(low, @core.HULL_FULL), 12),
        ])
      }
    }
    println("")
  }
}

///|
fn post_name(p : @core.Post) -> String {
  match p {
    Drive => "drive"
    Hull => "hull"
    Craft => "craft"
  }
}

///|
fn phase_name(p : @core.Phase) -> String {
  match p {
    Burn => "burn"
    Coast => "coast"
    Approach => "approach"
    Arrived => "arrived"
  }
}

///|
/// One player's check-ins on one crossing, as they would meet them: what
/// was new, what each post would lead to, and what they chose.
fn story() -> Unit {
  let base = @sim.scenarios()[0]
  for name in ["EF-147 The Tigress", "HS-212 The Twin-Tailed Scorpion"] {
    let p = @ships.profiles().filter(p => p.name == name)[0]
    for distance in [8.0, 20.0] {
      let actors = base.actors.copy()
      actors[0] = { ..actors[0], policy: Thoughtful, }
      let s = {
        ..base,
        ship: p,
        route: { ..p.route, distance_ly: distance, },
        actors,
      }
      let r = s.run(3)
      println(
        "== story: thoughtful player on \{p.name}, \{distance.to_int()} ly, arrived \{hours(r.arrived_at)} h of \{hours(r.plan.fastest())}–\{hours(r.plan.slowest())}",
      )
      for d in r.decisions {
        guard d.actor == @sim.actor_id(0) else { continue }
        let at = r.samples.search_by(x => x.t >= d.t).map(i => r.samples[i])
        let phase = at.map(x => phase_name(x.phase)).unwrap_or("?")
        let hull = at.map(x => pct(x.hull, @core.HULL_FULL)).unwrap_or("?")
        let from = d.from.map(post_name).unwrap_or("-")
        println(
          "  \{hours(d.t)} h \{phase}, hull \{hull}: \{d.news} new; \{from} -> \{post_name(d.to)}" +
          (if d.watch > 0L { ", \{d.watch / 3600L} h watch" } else { "" }) +
          "; arrival \{hours(d.before)} -> \{hours(d.after)} (spread \{d.leverage / 60L} min, \{d.undominated} undominated)",
        )
      }
      let t = r.last.tallies.get(@sim.actor_id(0)).unwrap()
      println(
        "  ends: works \{t.work * 10L / @core.WORK_SIZE} tenths, regard \{t.regard / @core.REGARD_HOUR} h, watches \{t.watches_stood}/\{t.watches_broken}; demands " +
        r.last.demands
        .map(d => {
          "\{hazard_name(d.hazard)} \{phase_name(d.phase)} \{if d.status == Met { "met" } else { "missed" }}"
        })
        .join(", "),
      )
      println("")
    }
  }
}

///|
fn main {
  let args = @env.args()
  let section = args.get(1).unwrap_or("all")
  let runs = args
    .get(2)
    .map(a => @string.parse_int(a) catch { _ => 30 })
    .unwrap_or(30)
  let all = section == "all"
  if all || section == "envelopes" {
    envelopes()
  }
  if all || section == "scenarios" {
    scenarios(runs)
  }
  if all || section == "ships" {
    ships(runs)
  }
  if all || section == "policies" {
    policies(runs)
  }
  if all || section == "voyages" {
    voyages()
  }
  if all || section == "careers" {
    careers(runs)
  }
  if all || section == "story" {
    story()
  }
}
