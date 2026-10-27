///|
/// Hours to one decimal: "11.9".
fn hours(ticks : Int64) -> String {
  let tenths = (ticks.to_double() / 360.0).round().to_int64()
  "\{tenths / 10L}.\{tenths.abs() % 10L}"
}

///|
/// Elapsed time as h:mm: "11:54".
fn clock(ticks : Int64) -> String {
  let minutes = ticks / 60L
  let mm = minutes % 60L
  "\{minutes / 60L}:\{if mm < 10L { "0" } else { "" }}\{mm}"
}

///|
/// Signed whole minutes with a true minus sign: "−42", "+7", "0".
fn minutes_delta(ticks : Int64) -> String {
  let m = ticks / 60L
  if m < 0L {
    "\u{2212}\{-m}"
  } else if m > 0L {
    "+\{m}"
  } else {
    "0"
  }
}

///|
fn percent(part : Int64, whole : Int64) -> String {
  guard whole > 0L else { "0%" }
  "\{part * 100L / whole}%"
}

///|
fn hull_percent(hull : Int64) -> String {
  percent(hull, @core.HULL_FULL)
}

///|
/// A drive setting in thousandths as a decimal: "0.837".
fn setting(s : Int64) -> String {
  let frac = (s % 1000L).to_string()
  "\{s / 1000L}.\{"000"[:3 - frac.length()]}\{frac}"
}

///|
fn post_name(post : @core.Post) -> String {
  match post {
    Drive => "drive"
    Hull => "hull"
    Craft => "craft"
  }
}

///|
fn phase_name(phase : @core.Phase) -> String {
  match phase {
    Burn => "burn"
    Coast => "coast"
    Approach => "approach"
    Arrived => "arrived"
  }
}

///|
/// Thousands separators for a whole number: "24,000".
fn grouped(n : Int64) -> String {
  let digits = n.abs().to_string()
  let out = StringBuilder()
  for i, c in digits {
    if i > 0 && (digits.length() - i) % 3 == 0 {
      out.write_char(',')
    }
    out.write_char(c)
  }
  if n < 0L {
    "\u{2212}\{out}"
  } else {
    out.to_string()
  }
}
