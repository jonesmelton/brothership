// The story: what a player would be told, derived from the log. Phases,
// demands and refits change inside ticks, so they are found by comparing
// the states either side of a row, not by reading the row.

///|
/// Something a player would be told. Derived, never stored.
pub(all) enum Happening {
  /// The ship left port.
  Departed
  /// A phase began; `Arrived` is the arrival.
  Began(phase~ : Phase)
  /// The ship docked; `recruits` joined at this port.
  Docked(recruits~ : Int64)
  Opened(hazard~ : Hazard)
  Met(hazard~ : Hazard)
  Missed(hazard~ : Hazard)
  /// A refit landed, raising it to `level`.
  Landed(refit~ : Refit, level~ : Int64)
  /// The ship changed what it asks for.
  Asked(post~ : Post?)
  /// `crew` took `post`, by choice or by a standing order, joining if new.
  Took(crew~ : String, post~ : Post)
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
  match event {
    Spoke(line~, about~) => return [Happening::Spoke(line~, about~)]
    Promoted(crew~, rank~) => {
      let tally = match before.crossing() {
        Some(c) => c.tallies.get(crew).unwrap_or(no_tally)
        None => no_tally
      }
      return [Promoted(crew~, rank~, tally~)]
    }
    Docked => {
      out.push(Docked(recruits=after.ship.recruits - before.ship.recruits))
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
    _ => ()
  }
  out
}
