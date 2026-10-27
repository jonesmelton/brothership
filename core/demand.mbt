///|
/// A demand for hours on one post before its phase ends. See "events" in
/// `docs/gameplay.md`.
pub(all) enum Hazard {
  /// Hull hands before the phase ends, or the hull loses a quarter.
  Breach
  /// Drive hands before the phase ends, or the hull loses a sixth.
  Flare
  /// Craft hands before the coast ends, for refit progress. Nothing is lost
  /// by letting it go.
  Salvage
} derive(Debug, Eq, Compare, Hash, ToJson, FromJson)

///|
pub fn Hazard::post(self : Hazard) -> Post {
  match self {
    Breach => Hull
    Flare => Drive
    Salvage => Craft
  }
}

///|
pub(all) enum Status {
  Waiting
  Open
  Met
  Missed
} derive(Debug, Eq, Compare, ToJson, FromJson)

///|
pub(all) struct Demand {
  hazard : Hazard
  phase : Phase
  /// Opens once the phase's stock has fallen to this.
  opens_at : Int64
  /// Quarter-hand-ticks on the hazard's post.
  need : Int64
  done : Int64
  status : Status
} derive(Debug, Eq, ToJson, FromJson)

///|
pub const BREACH_LOSS : Int64 = 250_000_000L

///|
pub const FLARE_LOSS : Int64 = 166_666_666L

///|
/// Refit progress a met salvage adds: three crew-hours of engineering.
pub const SALVAGE_YIELD : Int64 = 172_800L

///|
/// Counter-based randomness: a hash of the ship's seed, the crossing and a
/// logical index. Nothing a crew does during a crossing changes its demands.
fn mix(x : UInt64) -> UInt64 {
  let x = x + 0x9E3779B97F4A7C15UL
  let x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9UL
  let x = (x ^ (x >> 27)) * 0x94D049BB133111EBUL
  x ^ (x >> 31)
}

///|
fn draw(seed : Int64, crossing : Int64, index : Int64, n : Int64) -> Int64 {
  let h = mix(
    mix(mix(seed.reinterpret_as_uint64()) ^ crossing.reinterpret_as_uint64()) ^
    index.reinterpret_as_uint64(),
  )
  (h % n.reinterpret_as_uint64()).reinterpret_as_int64()
}

///|
/// One or two demands, drawn from the ship's seed and crossing count. Each
/// opens between a fifth and two thirds of the way through its phase.
pub fn demands_for(
  plan : Plan,
  seed : Int64,
  crossing : Int64,
) -> Array[Demand] {
  let n = 1L + draw(seed, crossing, 0, 2)
  Array::makei(n.to_int(), i => {
    let i = i.to_int64() * 8L
    let roll = (k : Int64, n : Int64) => draw(seed, crossing, i + k, n)
    let hazard = if plan.coast > 0L && roll(1, 3) == 0L {
      Salvage
    } else if roll(2, 2) == 0L {
      Breach
    } else {
      Flare
    }
    let (phase, stock) = match hazard {
      Salvage => (Coast, plan.coast)
      _ => (if roll(3, 2) == 0L { Burn } else { Approach }, plan.burn)
    }
    let permille = 333L + roll(4, 468)
    let hours = match hazard {
      Breach => 3L + roll(5, 4)
      Flare => 4L + roll(5, 5)
      Salvage => 8L + roll(5, 9)
    }
    {
      hazard,
      phase,
      opens_at: stock / 1000L * permille,
      need: hours * HOUR * HAND / 2L,
      done: 0,
      status: Waiting,
    }
  })
}
