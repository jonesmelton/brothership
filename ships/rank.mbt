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
  let caps = rank_caps(aboard.length().to_int64())
  let counts = Array::make(caps.length(), 0L)
  for pair in aboard {
    counts[pair.1.to_int()] += 1L
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
  let out = []
  for cand in candidates {
    let (crew, rank, _) = cand
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
