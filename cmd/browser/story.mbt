// The ship's story on this screen: the log, "while you were away", and what
// is read aloud as it happens. See docs/accessibility.md.

///|
/// The client's copy of one ship's story.
struct Told {
  /// Entries so far, oldest first.
  entries : Array[@core.Entry]
  /// The newest `seq` when this visit's first story arrived; `None` before
  /// it does. Entries after it are news of this visit, not of the absence.
  arrived : Int64?
  /// The ship is writing a line.
  speaking : Bool
  /// The ship's mind is weighing a choice.
  thinking : Bool
} derive(Eq)

///|
fn Told::new() -> Told {
  { entries: [], arrived: None, speaking: false, thinking: false, }
}

///|
/// The newest `seq` held, or 0.
fn Told::last(self : Told) -> Int64 {
  self.entries.last().map(e => e.seq).unwrap_or(0L)
}

///|
/// What the player wants read aloud as it happens. Kept in `localStorage`.
enum Hear {
  Everything
  Urgent
  Nothing
} derive(Eq)

///|
fn Hear::name(self : Hear) -> String {
  match self {
    Everything => "everything"
    Urgent => "urgent"
    Nothing => "nothing"
  }
}

///|
fn Hear::parse(s : String) -> Hear {
  match s {
    "urgent" => Urgent
    "nothing" => Nothing
    _ => Everything
  }
}

///|
/// Text for the two live regions. `count` changes with every update so the
/// same words can be spoken twice.
struct Said {
  polite : String
  assertive : String
  count : Int32
} derive(Eq)

///|
/// The most sentences one announcement reads before pointing to the log.
const MOST_SPOKEN : Int32 = 3

///|
/// Up to `MOST_SPOKEN` sentences, then how many more wait in the log.
fn capped(lines : Array[String]) -> String {
  if lines.length() <= MOST_SPOKEN {
    lines.join(" ")
  } else {
    let more = (lines.length() - MOST_SPOKEN).to_int64()
    lines[:MOST_SPOKEN].join(" ") +
    " And \{@words.plural(more, "more", "more")} in the log."
  }
}

///|
/// Merge `incoming` into `told`, and say what of it the player hears now,
/// as polite and assertive text. The first story of a visit is never read
/// aloud: "while you were away" tells it.
fn Told::merge(
  self : Told,
  incoming : @core.Story,
  you~ : String,
  hear~ : Hear,
  ship~ : String,
) -> (Told, String, String) {
  let last = self.last()
  let fresh = incoming.entries.filter(e => e.seq > last)
  let entries = self.entries + fresh
  let next = {
    entries,
    arrived: Some(
      self.arrived.unwrap_or(entries.last().map(e => e.seq).unwrap_or(0L)),
    ),
    speaking: incoming.speaking,
    thinking: incoming.thinking,
  }
  guard self.arrived is Some(_) && hear != Nothing else { (next, "", "") }
  let polite = []
  let assertive = []
  for e in fresh {
    match @words.priority(e, you~, story=entries) {
      Interrupt => assertive.push(@words.told(e.happening, you~, ship~))
      Announce if hear == Everything =>
        polite.push(@words.told(e.happening, you~, ship~))
      _ => ()
    }
  }
  (next, capped(polite), capped(assertive))
}

///|
/// "While you were away": what happened between the player's last visit,
/// at `seen`, and this one, leaving out what is kept in the log only. `on`
/// picks the entries of one page.
fn Told::away(
  self : Told,
  seen : Int64?,
  you~ : String,
  ship~ : String,
  on~ : (@core.Entry) -> Bool = _ => true,
) -> Array[String] {
  guard seen is Some(seen) else { [FIRST_VISIT] }
  guard self.arrived is Some(arrived) else { [] }
  let lines = self.entries
    .filter(e => {
      e.seq > seen &&
      e.seq <= arrived &&
      on(e) &&
      @words.priority(e, you~, story=self.entries) != Quiet
    })
    .map(e => @words.told(e.happening, you~, ship~))
  if lines.is_empty() {
    [NOTHING_NEW]
  } else {
    lines
  }
}

///|
const FIRST_VISIT : String = "This is your first visit to this ship."

///|
const NOTHING_NEW : String = "Nothing new since your last visit."
