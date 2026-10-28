///|
/// Ticks in an hour, for rates shown per hour.
pub const TICKS_PER_HOUR : Int64 = 3600L

///|
/// `delta` over `span` ticks as a rate per hour, rounded toward negative
/// infinity, so `result * span <= delta * 3600 < (result + 1) * span`.
/// `delta` may be negative (a hull that wears).
pub fn per_hour(
  delta : Int64,
  span : Int64,
) -> Int64 where {
  proof_require: per_hour_pre(delta, span),
  proof_ensure: result => per_hour_post(delta, span, result),
} {
  let scaled = delta * TICKS_PER_HOUR
  if scaled >= 0L {
    scaled / span
  } else {
    // `/` truncates toward zero; a negative inexact quotient is one too high.
    -((span - 1L - scaled) / span)
  }
}
