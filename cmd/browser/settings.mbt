// The Ship page's settings besides what is read aloud: sounds, the typeface,
// and how a batch of sentences reaches a screen reader. See
// docs/accessibility.md.

///|
/// Whether a short tone marks a happening that is read aloud. Kept in
/// `localStorage`; off until the player turns it on.
enum Sounds {
  On
  Off
} derive(Eq, Debug)

///|
fn Sounds::name(self : Sounds) -> String {
  match self {
    On => "on"
    Off => "off"
  }
}

///|
fn Sounds::parse(s : String) -> Sounds {
  match s {
    "on" => On
    _ => Off
  }
}

///|
/// The faces the page is set in. Kept in `localStorage`.
enum Face {
  Book
  Legible
} derive(Eq, Debug)

///|
fn Face::name(self : Face) -> String {
  match self {
    Book => "book"
    Legible => "legible"
  }
}

///|
fn Face::parse(s : String) -> Face {
  match s {
    "legible" => Legible
    _ => Book
  }
}

///|
/// `document.ariaNotify`'s priority.
enum NotifyPriority {
  Normal
  High
} derive(Eq, Debug)

///|
fn NotifyPriority::name(self : NotifyPriority) -> String {
  match self {
    Normal => "normal"
    High => "high"
  }
}

///|
/// One string for a batch, because some screen readers speak only the most
/// recent `ariaNotify` call. An interrupt goes first and makes the whole
/// batch `High`.
fn notice(polite : String, assertive : String) -> (String, NotifyPriority)? {
  match (polite, assertive) {
    ("", "") => None
    (p, "") => Some((p, Normal))
    ("", a) => Some((a, High))
    (p, a) => Some((a + " " + p, High))
  }
}

///|
/// How a batch reaches the screen reader: through `ariaNotify` when the
/// browser has it, otherwise through the two live regions. Never both.
enum Delivery {
  Nothing
  Notify(String, NotifyPriority)
  Regions(String, String)
} derive(Eq, Debug)

///|
fn delivery(native~ : Bool, polite~ : String, assertive~ : String) -> Delivery {
  match (native, notice(polite, assertive)) {
    (_, None) => Nothing
    (true, Some((text, priority))) => Notify(text, priority)
    (false, _) => Regions(polite, assertive)
  }
}

///|
/// A sound for a happening that is read aloud, quietest first: a tone for an
/// announcement, a line from the ship, a two-note figure for an interrupt.
enum Cue {
  Tone
  Line
  Alarm
} derive(Eq, Debug)

///|
fn Cue::rank(self : Cue) -> Int32 {
  match self {
    Tone => 0
    Line => 1
    Alarm => 2
  }
}

///|
/// The louder of the cue so far, if any, and `b`.
fn louder(a : Cue?, b : Cue) -> Cue {
  match a {
    Some(a) if a.rank() >= b.rank() => a
    _ => b
  }
}

///|
/// The cue to play, if sounds are on.
fn cue_for(sounds : Sounds, cue : Cue?) -> Cue? {
  match sounds {
    On => cue
    Off => None
  }
}

///|
/// A sine note: pitch in hertz, start and length in milliseconds, and peak
/// gain.
struct Note {
  hz : Double
  at_ms : Double
  ms : Double
  gain : Double
} derive(Eq, Debug)

///|
/// Every cue ends within 400 ms and peaks at or below 0.2 gain.
fn Cue::notes(self : Cue) -> Array[Note] {
  match self {
    Tone => [{ hz: 660.0, at_ms: 0.0, ms: 180.0, gain: 0.12, }]
    Line => [{ hz: 440.0, at_ms: 0.0, ms: 220.0, gain: 0.07, }]
    Alarm =>
      [
        { hz: 880.0, at_ms: 0.0, ms: 110.0, gain: 0.16, },
        { hz: 587.0, at_ms: 130.0, ms: 150.0, gain: 0.16, },
      ]
  }
}

///|
/// Send a batch of sentences to the screen reader by `delivery`: the live
/// regions' text changes in the model, or `ariaNotify` is called.
fn Model::say(
  self : Model,
  polite~ : String,
  assertive~ : String,
) -> (Model, @rabbita.Cmd) {
  match delivery(native=self.notify, polite~, assertive~) {
    Nothing => (self, @rabbita.none)
    Notify(text, priority) =>
      (self, @rabbita.effect(() => aria_notify(text, priority.name())))
    Regions(polite, assertive) =>
      (
        { ..self, said: { polite, assertive, count: self.said.count + 1, }, },
        @rabbita.none,
      )
  }
}

///|
/// The settings menu, a page of its own. It is not one of the ship's pages,
/// so the ship's stage, log and voice stay out of it.
fn settings_page(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> Array[@rabbita.Html] {
  let number = if model.officer == "" {
    [@html.p("Your service number arrives with the session.")]
  } else {
    [
      @html.p(class="designation", model.officer),
      @html.p(
        "This is how the ship knows you. It is the name other officers see.",
      ),
    ]
  }
  let back = if model.ship is Some(_) {
    "Back to the ship"
  } else {
    "Back to the fleet"
  }
  [
    @html.p([@html.a(href="#ship", class="control", back)]),
    @html.section([@html.h2("Your service number"), ..number]),
    @html.section([
      @html.h2("Preferences"),
      @html.p("These are kept in this browser."),
      toggles(
        "hear",
        "Read aloud as it happens",
        [
          (Everything, "Everything"),
          (Urgent, "Urgent only"),
          (Nothing, "Nothing"),
        ],
        model.hear,
        h => Hear(h),
        emit,
      ),
      toggles(
        "sounds",
        "Sounds",
        [(On, "On"), (Off, "Off")],
        model.sounds,
        s => Sound(s),
        emit,
      ),
      toggles(
        "face",
        "Type",
        [(Book, "Book"), (Legible, "Legible")],
        model.face,
        f => Typeface(f),
        emit,
      ),
    ]),
  ]
}

///|
/// Play `cue` if sounds are on.
fn Model::chime(self : Model, cue : Cue?) -> @rabbita.Cmd {
  match cue_for(self.sounds, cue) {
    Some(c) =>
      @rabbita.effect(() => {
        for n in c.notes() {
          play_note(n.hz, n.at_ms, n.ms, n.gain)
        }
      })
    None => @rabbita.none
  }
}
