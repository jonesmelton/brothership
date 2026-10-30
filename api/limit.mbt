///|
/// A rate limiter keyed by client: each key may take `burst` tokens at once
/// and regains one every `interval` seconds (the generic cell rate
/// algorithm). It stores one Int64 per key that has recently been refused
/// or served, and drops a key once it has fully recovered.
pub struct Limiter {
  priv burst : Int64
  priv interval : Int64
  priv next : Map[String, Int64]
}

///|
/// Keys held before `take` sweeps out the recovered ones.
const SWEEP_AT : Int32 = 4096

///|
pub fn Limiter::new(burst~ : Int32, interval~ : Int32) -> Limiter {
  { burst: burst.to_int64(), interval: interval.to_int64(), next: Map([]), }
}

///|
/// Takes a token for `key` at `now`, in Unix seconds. Returns 0 if it was
/// available, otherwise the seconds until one is, and takes nothing.
pub fn Limiter::take(self : Limiter, key : String, now~ : Int64) -> Int64 {
  if self.next.length() >= SWEEP_AT {
    self.next.retain((_, at) => at > now)
  }
  let at = self.next.get(key).unwrap_or(now).max(now)
  let wait = at - now - (self.burst - 1L) * self.interval
  if wait > 0L {
    return wait
  }
  self.next[key] = at + self.interval
  0L
}
