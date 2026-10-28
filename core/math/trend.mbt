///|
/// Ticks in an hour, for rates shown per hour.
pub const TICKS_PER_HOUR : Int64 = 3600L

///|
/// `delta` over `span` ticks as a rate per hour, rounded toward negative
/// infinity, so `result * span <= delta * 3600 < (result + 1) * span`.
/// `delta` may be negative (a hull that wears).
pub fn per_hour(delta : Int64, span : Int64) -> Int64 {
  ignore((delta, span))
  ...
}
