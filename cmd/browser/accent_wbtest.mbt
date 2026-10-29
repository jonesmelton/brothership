///|
fn accent_for(pennant : String) -> (String, String) {
  match accent_of_pennant(pennant) {
    Some(pair) => pair
    None => abort("no accent for \{pennant}")
  }
}

///|
fn digit_of(c : Char) -> Int32 {
  match c {
    '0' => 0
    '1' => 1
    '2' => 2
    '3' => 3
    '4' => 4
    '5' => 5
    '6' => 6
    '7' => 7
    '8' => 8
    '9' => 9
    'a' => 10
    'b' => 11
    'c' => 12
    'd' => 13
    'e' => 14
    'f' => 15
    _ => abort("not a lowercase hex digit: \{c}")
  }
}

///|
fn rgb(hex : String) -> (Double, Double, Double) {
  let digits : Array[Int32] = []
  for c in hex {
    if c != '#' {
      digits.push(digit_of(c))
    }
  }
  guard digits.length() == 6 else { abort("not a #rrggbb colour: \{hex}") }
  let ch = i => (digits[i] * 16 + digits[i + 1]).to_double() / 255.0
  (ch(0), ch(2), ch(4))
}

///|
fn linear(c : Double) -> Double {
  if c <= 0.04045 {
    c / 12.92
  } else {
    @cmath.pow((c + 0.055) / 1.055, 2.4)
  }
}

///|
fn luminance(hex : String) -> Double {
  let (r, g, b) = rgb(hex)
  0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

///|
fn contrast(a : String, b : String) -> Double {
  let la = luminance(a)
  let lb = luminance(b)
  let (hi, lo) = if la > lb { (la, lb) } else { (lb, la) }
  (hi + 0.05) / (lo + 0.05)
}

///|
fn lab(hex : String) -> (Double, Double, Double) {
  let (r, g, b) = rgb(hex)
  let (lr, lg, lb) = (linear(r), linear(g), linear(b))
  let f = t => {
    if t > 0.008856 {
      @cmath.cbrt(t)
    } else {
      7.787 * t + 16.0 / 116.0
    }
  }
  let x = f((0.4124 * lr + 0.3576 * lg + 0.1805 * lb) / 0.95047)
  let y = f(0.2126 * lr + 0.7152 * lg + 0.0722 * lb)
  let z = f((0.0193 * lr + 0.1192 * lg + 0.9505 * lb) / 1.08883)
  (116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z))
}

///|
/// CIE76 difference. Around 2.3 is a just-noticeable difference; the cast's
/// accents are kept 30 or more apart so they tell apart at a glance.
fn delta_e(a : String, b : String) -> Double {
  let (l1, a1, b1) = lab(a)
  let (l2, a2, b2) = lab(b)
  let (dl, da, db) = (l1 - l2, a1 - a2, b1 - b2)
  @cmath.pow(dl * dl + da * da + db * db, 0.5)
}

///|
test "relative luminance follows WCAG 2.x" {
  assert_eq(luminance("#000000"), 0.0)
  assert_true(luminance("#ffffff") > 0.9999 && luminance("#ffffff") < 1.0001)
  assert_true(contrast("#ffffff", "#000000") > 20.99)
  assert_true(contrast("#000000", "#ffffff") > 20.99)
}

///|
test "each starting ship's accent meets its contrast floors in each scheme" {
  for pennant in ["EF-147", "EF-287", "HS-212"] {
    let (light, dark) = accent_for(pennant)
    assert_true(contrast(light, "#f0e7d5") >= 4.5)
    assert_true(contrast(light, "#c9bca4") >= 3.0)
    assert_true(contrast(dark, "#0f1513") >= 4.5)
    assert_true(contrast(dark, "#2b3630") >= 3.0)
  }
}

///|
test "the starting ships' accents are pairwise distinct in each scheme" {
  let pennants = ["EF-147", "EF-287", "HS-212"]
  for i = 0; i < pennants.length(); i = i + 1 {
    for j = i + 1; j < pennants.length(); j = j + 1 {
      let (li, di) = accent_for(pennants[i])
      let (lj, dj) = accent_for(pennants[j])
      assert_true(delta_e(li, lj) >= 30.0)
      assert_true(delta_e(di, dj) >= 30.0)
    }
  }
}

///|
test "a ship outside the cast gets no accent style" {
  assert_eq(accent_style("a plain ship"), [])
}

///|
test "the cast's accent style sets both schemes on the ship" {
  let style = accent_style("EF-147 The Tigress")
  let (light, dark) = accent_for("EF-147")
  assert_eq(style, [
    "--ship-accent-light: \{light}",
    "--ship-accent-dark: \{dark}",
  ])
}
