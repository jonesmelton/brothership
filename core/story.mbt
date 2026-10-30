// The story: what a player would be told, derived from the log. Phases,
// demands and refits change inside ticks, so they are found by comparing
// the states either side of a row, not by reading the row.

///|
/// What a crossing came to, told when the ship docks: the leg it flew, the
/// ticks aboard until arrival, the works it delivered and the plan it flew,
/// from which the years at the worlds follow.
pub(all) struct Landing {
  /// Crossings flown before this one: names the leg in the itinerary.
  leg : Int64
  /// Ticks aboard until arrival.
  aboard : Int64
  /// Works delivered across the crew.
  works : Int64
  plan : Plan
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Something a player would be told. Derived, never stored.
pub(all) enum Happening {
  /// The ship left port.
  Departed
  /// A phase began; `Arrived` is the arrival.
  Began(phase~ : Phase)
  /// The ship docked; `recruits` joined at this port.
  Docked(recruits~ : Int64, landing~ : Landing)
  Opened(hazard~ : Hazard)
  Met(hazard~ : Hazard)
  Missed(hazard~ : Hazard)
  /// A refit landed, raising it to `level`.
  Landed(refit~ : Refit, level~ : Int64)
  /// The ship changed what it asks for.
  Asked(post~ : Post?)
  /// `crew` signed on to the ship.
  Signed(crew~ : String)
  /// `crew` left the ship: at the dock, for leaving or for doing nothing
  /// the whole voyage, or at once in port.
  Discharged(crew~ : String)
  /// `crew` took `post`, by choice or by a standing order.
  Took(crew~ : String, post~ : Post)
  /// `crew` stood down from their post, staying aboard.
  Left(crew~ : String)
  /// `crew` stood a watch to its end.
  Stood(crew~ : String)
  /// `crew` finished a work.
  Finished(crew~ : String)
  /// `crew` made their banked work: `units` of it, at `percent` of the bank.
  /// Not told for the making at 100 percent when a hand leaves or the ship
  /// docks.
  Made(crew~ : String, craft~ : Craft, units~ : Int64, percent~ : Int64)
  /// The ship promoted `crew` to `rank`; `tally` is what they did this
  /// crossing.
  Promoted(crew~ : String, rank~ : Int64, tally~ : Tally)
  /// The ship chose to coast at `cruise` thousandths of its cap.
  Cruised(cruise~ : Int64)
  Spoke(line~ : String, about~ : Int64)
} derive(Debug, Eq, ToJson, FromJson)

///|
/// What applying `event` to `before`, giving `after`, tells a player, in
/// a fixed order: a making, the voyage, demands, refits, the ask, then crew.
pub fn happenings(
  before : State,
  event : Event,
  after : State,
) -> Array[Happening] {
  let out : Array[Happening] = []
  // Who signed on and who left the ship.
  let roster = () => {
    for crew, _ in after.officers {
      if !before.officers.contains(crew) {
        out.push(Signed(crew~))
      }
    }
    for crew, _ in before.officers {
      if !after.officers.contains(crew) {
        out.push(Discharged(crew~))
      }
    }
  }
  match event {
    Spoke(line~, about~) => return [Happening::Spoke(line~, about~)]
    Cruising(cruise~) =>
      return if before.ship.cruise == cruise { [] } else { [Cruised(cruise~)] }
    Promoted(crew~, rank~) => {
      let tally = match before.crossing() {
        Some(c) => c.tallies.get(crew).unwrap_or(no_tally)
        None => no_tally
      }
      return [Promoted(crew~, rank~, tally~)]
    }
    Docked => {
      let (aboard, plan) = match before.crossing() {
        Some(c) => (c.arrived_at.unwrap_or(c.t), c.plan)
        None =>
          (0L, Plan::{ burn: 0L, coast: 0L, eta_rate: 0L, coast_rate: 0L, })
      }
      let mut works = 0L
      for crew, r in after.ship.records {
        works += r.works -
          before.ship.records.get(crew).map(x => x.works).unwrap_or(0L)
      }
      out.push(
        Docked(recruits=after.ship.recruits - before.ship.recruits, landing={
          leg: before.ship.crossings,
          aboard,
          works,
          plan,
        }),
      )
      roster()
      return out
    }
    _ => ()
  }
  match (before.crossing(), after.crossing()) {
    (None, Some(_)) => out.push(Departed)
    (Some(a), Some(b)) => {
      if event is Crew(crew~, intent=Made) && a.hands.get(crew) is Some(h) {
        let percent = craft_percent(a.ship.seed, crew, a.t)
        out.push(
          Made(crew~, craft=h.craft, units=h.banked * percent / 100L, percent~),
        )
      }
      if b.phase > a.phase {
        // A long tick can cross more than one phase.
        let phases : Array[Phase] = [Coast, Approach, Arrived]
        for p in phases {
          if p > a.phase && p <= b.phase {
            out.push(Began(phase=p))
          }
        }
      }
      for i, d in b.demands {
        let was = a.demands.get(i).map(x => x.status)
        guard was != Some(d.status) else { continue }
        match d.status {
          Open => out.push(Opened(hazard=d.hazard))
          Met => out.push(Met(hazard=d.hazard))
          Missed => out.push(Missed(hazard=d.hazard))
          Waiting => ()
        }
      }
      for r in refits {
        if b.fit.level(r) > a.fit.level(r) {
          out.push(Landed(refit=r, level=b.fit.level(r)))
        }
      }
      if b.ask != a.ask {
        out.push(Asked(post=b.ask))
      }
      roster()
      for crew, h in b.hands {
        if a.hands.get(crew).map(x => x.post) != Some(h.post) {
          out.push(Took(crew~, post=h.post))
        }
      }
      for crew, _ in a.hands {
        if !b.hands.contains(crew) {
          out.push(Left(crew~))
        }
      }
      for crew, y in b.tallies {
        guard a.tallies.get(crew) is Some(x) else { continue }
        if y.watches_stood > x.watches_stood {
          out.push(Stood(crew~))
        }
        if y.work / WORK_SIZE > x.work / WORK_SIZE {
          out.push(Finished(crew~))
        }
      }
    }
    (None, None) => roster()
    (Some(_), None) => ()
  }
  out
}
