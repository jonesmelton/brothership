///|
/// Largest representable clock value. `Int64` is 64-bit on every target, so
/// the bound is identical on the client and the server.
pub const MAX_CLOCK : Int64 = 9223372036854775807L

///|
pub fn advance(
  clock : Int64,
  ticks : Int64,
) -> Int64 where {
  proof_require: advance_pre(clock, ticks),
  proof_ensure: result => advance_post(clock, ticks, result),
} {
  clock + ticks
}

///|
/// Total form of `advance`: `None` exactly when the step would leave the
/// clock's valid range.
pub fn try_advance(
  clock : Int64,
  ticks : Int64,
) -> Int64? where {
  proof_require: clock_ok(clock),
  proof_ensure: result => try_advance_post(clock, ticks, result),
} {
  if ticks > 0 && clock <= MAX_CLOCK - ticks {
    Some(advance(clock, ticks))
  } else {
    None
  }
}
