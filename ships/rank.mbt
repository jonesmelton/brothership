///|
/// How many officers a ship may hold at each rank, indexed by rank, for a
/// ship with `officers` officers aboard. `None` is no cap. The pyramid is
/// 1:2:3:4 from commander down and ignores `officers` for now.
pub fn rank_caps(_officers : Int64) -> Array[Int64?] {
  [None, Some(4L), Some(3L), Some(2L), Some(1L)]
}

///|
/// The promotions an arrived crossing earns, as (crew, new rank). Candidates
/// are the hands aboard for which `officer` holds and whose regard,
/// including this crossing's, makes a higher rank available. Each moves up
/// one rank at most, in order of total regard (then crew id), and only into
/// a rank with room under `rank_caps` once earlier promotions in the pass are
/// counted. Nobody is demoted. Empty if the crossing has not arrived.
pub fn promotions(
  c : @core.Crossing,
  officer~ : (String) -> Bool,
) -> Array[(String, Int64)] {
  guard c.phase == Arrived else { return [] }
  let aboard = []
  for crew, h in c.hands {
    if officer(crew) {
      aboard.push((crew, h.rank))
    }
  }
  let candidates = []
  for pair in aboard {
    let (crew, rank) = pair
    let regard = c.ship.records.get(crew).map(r => r.regard).unwrap_or(0L) +
      c.tallies.get(crew).map(t => t.regard).unwrap_or(0L)
    if @core.rank_floor(regard) > rank {
      candidates.push((crew, rank, regard))
    }
  }
  candidates.sort_by((a, b) => {
    let by_regard = b.2.compare(a.2)
    if by_regard != 0 {
      by_regard
    } else {
      a.0.compare(b.0)
    }
  })
  allowed(c, candidates.map(cand => cand.0), officer~)
}

///|
/// The promotions `picks` asks for, as (crew, new rank), that an arrived
/// crossing allows: each a hand aboard for which `officer` holds, once, one
/// rank up to at most commander, and only into a rank with room under
/// `rank_caps` once earlier picks are counted. Picks are taken in order, so
/// an earlier pick can free or fill a rank for a later one.
pub fn allowed(
  c : @core.Crossing,
  picks : Array[String],
  officer~ : (String) -> Bool,
) -> Array[(String, Int64)] {
  guard c.phase == Arrived else { return [] }
  let aboard = []
  for crew, h in c.hands {
    if officer(crew) {
      aboard.push(h.rank)
    }
  }
  let caps = rank_caps(aboard.length().to_int64())
  let counts = Array::make(caps.length(), 0L)
  for rank in aboard {
    counts[rank.to_int()] += 1L
  }
  let out : Array[(String, Int64)] = []
  for crew in picks {
    guard officer(crew) && c.hands.get(crew) is Some(h) else { continue }
    guard !out.iter().any(p => p.0 == crew) else { continue }
    let rank = h.rank
    let next = rank + 1L
    guard next <= @core.COMMANDER else { continue }
    let room = match caps[next.to_int()] {
      Some(cap) => counts[next.to_int()] < cap
      None => true
    }
    if room {
      counts[rank.to_int()] -= 1L
      counts[next.to_int()] += 1L
      out.push((crew, next))
    }
  }
  out
}
