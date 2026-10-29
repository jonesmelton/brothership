///|
/// Ticks an ensign must serve aboard a ship before it can promote them.
/// About one short crossing, so the bottom rung is felt.
pub const ENSIGN_SERVICE : Int64 = 21_600L

///|
/// The ship can promote `crew` now: anyone above ensign, and an ensign who
/// has served `ENSIGN_SERVICE`.
pub fn eligible(c : @core.Crossing, crew : String) -> Bool {
  c.hands.get(crew) is Some(h) &&
  (h.rank > @core.ENSIGN || c.served(crew) >= ENSIGN_SERVICE)
}

///|
/// The promotions `picks` asks for, as (crew, new rank), that the crossing
/// allows: each a hand aboard for which `officer` holds and `eligible`
/// holds, once, one rank up to at most commander. How many hold each rank
/// is the ship's choice.
pub fn allowed(
  c : @core.Crossing,
  picks : Array[String],
  officer~ : (String) -> Bool,
) -> Array[(String, Int64)] {
  let out : Array[(String, Int64)] = []
  for crew in picks {
    guard officer(crew) && eligible(c, crew) else { continue }
    guard !out.iter().any(p => p.0 == crew) else { continue }
    let next = c.hands.get(crew).unwrap().rank + 1L
    if next <= @core.COMMANDER {
      out.push((crew, next))
    }
  }
  out
}

///|
/// The hands aboard for which `officer` and `keep` hold and that the ship
/// may promote, longest served first, then by crew id.
fn by_service(
  c : @core.Crossing,
  officer : (String) -> Bool,
  keep : (@core.Hand) -> Bool,
) -> Array[String] {
  let out = []
  for crew, h in c.hands {
    if officer(crew) && keep(h) && h.rank < @core.COMMANDER && eligible(c, crew) {
      out.push(crew)
    }
  }
  out.sort_by((a, b) => {
    let by = c.served(b).compare(c.served(a))
    if by != 0 {
      by
    } else {
      a.compare(b)
    }
  })
  out
}

///|
/// The scripted promotions at arrival, standing in for the ship's mind:
/// the longest-serving officer it may promote, one rank. Empty if the
/// crossing has not arrived.
pub fn promotions(
  c : @core.Crossing,
  officer~ : (String) -> Bool,
) -> Array[(String, Int64)] {
  guard c.phase == Arrived else { return [] }
  allowed(c, by_service(c, officer, _ => true)[:1].to_owned(), officer~)
}

///|
/// The officers aboard are bottom-heavy: at least two, three in four of them
/// ensigns, and one of those ensigns the ship may promote. A ship with a
/// mind holds a promotion cycle then, without waiting for arrival.
pub fn bottom_heavy(c : @core.Crossing, officer~ : (String) -> Bool) -> Bool {
  let mut officers = 0
  let mut ensigns = 0
  for crew, h in c.hands {
    if officer(crew) {
      officers += 1
      if h.rank == @core.ENSIGN {
        ensigns += 1
      }
    }
  }
  officers >= 2 &&
  ensigns * 4 >= officers * 3 &&
  !by_service(c, officer, h => h.rank == @core.ENSIGN).is_empty()
}

///|
/// The scripted promotion in a cycle held because the crew is bottom-heavy:
/// the longest-serving ensign the ship may promote.
pub fn first_ensign(
  c : @core.Crossing,
  officer~ : (String) -> Bool,
) -> Array[(String, Int64)] {
  let ensigns = by_service(c, officer, h => h.rank == @core.ENSIGN)
  allowed(c, ensigns[:1].to_owned(), officer~)
}
