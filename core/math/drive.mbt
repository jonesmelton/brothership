///|
/// The drive setting, in thousandths, when no one is aboard the drive.
pub const SETTING_FLOOR : Int64 = 350L

///|
/// The drive setting, in thousandths, at full burn.
pub const SETTING_FULL : Int64 = 1000L

///|
/// Largest stock, rate and span of ticks the kernels accept. Their products
/// stay inside `Int64`.
pub const MAX_STOCK : Int64 = 1000000000000000L

///|
pub const MAX_RATE : Int64 = 1000000000L

///|
pub const MAX_TICKS : Int64 = 1000000000L

///|
/// The drive setting in thousandths for `drive` hands when `needed` give full
/// burn, capped at `cap`. Never below `SETTING_FLOOR`, so a ship nobody
/// staffs still arrives, and never lower for one more hand.
pub fn setting(
  drive : Int64,
  needed : Int64,
  cap : Int64,
) -> Int64 where {
  proof_require: setting_pre(drive, needed, cap),
  proof_ensure: result => setting_post(drive, needed, cap, result),
} {
  let raw = if drive < needed {
    SETTING_FLOOR + 650L * (drive * (2L * needed - drive)) / (needed * needed)
  } else {
    SETTING_FULL
  }
  if raw < cap {
    raw
  } else {
    cap
  }
}

///|
/// `base` is the per-tick rate at full burn; the result is the per-tick rate
/// at `setting`. Rounds once, before any multiplication by time.
pub fn rate(
  base : Int64,
  setting : Int64,
) -> Int64 where {
  proof_require: rate_pre(base, setting),
  proof_ensure: result => result == rate_model(base, setting) && result >= 0L,
} {
  base * setting / 1000L
}

///|
/// What is left of a stock after `ticks` at `rate` per tick, stopping at zero.
pub fn deplete(
  left : Int64,
  rate : Int64,
  ticks : Int64,
) -> Int64 where {
  proof_require: deplete_pre(left, rate, ticks),
  proof_ensure: result => {
    result == deplete_model(left, rate, ticks) && 0L <= result && result <= left
  },
} {
  let spent = rate * ticks
  if spent < left {
    left - spent
  } else {
    0L
  }
}

///|
/// Exact ticks until `deplete` reaches zero: zero at the result and not one
/// tick sooner.
pub fn ticks_to_empty(
  left : Int64,
  rate : Int64,
) -> Int64 where {
  proof_require: 0L <= left &&
  left <= MAX_STOCK &&
  1L <= rate &&
  rate <= MAX_RATE,
  proof_ensure: result => empty_post(left, rate, result),
} {
  (left + rate - 1L) / rate
}

///|
/// A level after `ticks` at a signed `net` per tick, held within
/// `[0, ceiling]`.
pub fn settle(
  level : Int64,
  net : Int64,
  ticks : Int64,
  ceiling : Int64,
) -> Int64 where {
  proof_require: settle_pre(level, net, ticks, ceiling),
  proof_ensure: result => {
    result == settle_model(level, net, ticks, ceiling) &&
    0L <= result &&
    result <= ceiling
  },
} {
  let next = level + net * ticks
  if next < 0L {
    0L
  } else if next > ceiling {
    ceiling
  } else {
    next
  }
}
