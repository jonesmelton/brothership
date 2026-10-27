///|
/// Counter-based randomness: every draw is a hash of the run's seed and a
/// logical index, so a run replays exactly and no generator state is stored.
fn mix(x : UInt64) -> UInt64 {
  let x = x + 0x9E3779B97F4A7C15UL
  let x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9UL
  let x = (x ^ (x >> 27)) * 0x94D049BB133111EBUL
  x ^ (x >> 31)
}

///|
fn draw(seed : Int64, a : Int32, b : Int32, tag : Int32) -> UInt64 {
  mix(
    mix(mix(seed.reinterpret_as_uint64() ^ a.to_uint64()) ^ b.to_uint64()) ^
    tag.to_uint64(),
  )
}

///|
/// Uniform in `[0, n)`.
fn draw_below(
  seed : Int64,
  a : Int32,
  b : Int32,
  tag : Int32,
  n : Int64,
) -> Int64 {
  guard n > 0L else { 0L }
  (draw(seed, a, b, tag) % n.reinterpret_as_uint64()).reinterpret_as_int64()
}
