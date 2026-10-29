///|
/// Each cast ship's accent as (pennant, paper, night watch). Contrast and
/// spacing are checked in `accent_wbtest.mbt`.
fn accents() -> Array[(String, String, String)] {
  [
    ("EF-147", "#8a2a6b", "#e596c4"),
    ("EF-287", "#1f6e66", "#6fd1c0"),
    ("HS-212", "#33549e", "#9cb4f2"),
  ]
}

///|
fn accent_of_pennant(pennant : String) -> (String, String)? {
  accents().iter().find_first(a => a.0 == pennant).map(a => (a.1, a.2))
}

///|
fn accent_style(name : String) -> Array[String] {
  match @ships.profile_named(name).bind(p => p.title) {
    Some(t) =>
      match accent_of_pennant(t.pennant) {
        Some((light, dark)) =>
          ["--ship-accent-light: \{light}", "--ship-accent-dark: \{dark}"]
        None => []
      }
    None => []
  }
}
