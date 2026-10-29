///|
/// The local wall clock in Unix seconds.
fn unix_now() -> Int64 {
  date_now_ms().to_int64() / 1000L
}

///|
extern "js" fn date_now_ms() -> Double = "() => Date.now()"

///|
/// The newest story `seq` this browser has shown of `ship`, or "" if none.
extern "js" fn load_seen(ship : String) -> String =
  #|(ship) => localStorage.getItem("brothership.seen-seq." + ship) ?? ""

///|
extern "js" fn store_seen(ship : String, seq : String) -> Unit =
  #|(ship, seq) => localStorage.setItem("brothership.seen-seq." + ship, seq)

///|
/// The newest story `seq` viewed on each page of `ship`, as
/// `Viewed::name` gives it, or "".
extern "js" fn load_viewed(ship : String) -> String =
  #|(ship) => localStorage.getItem("brothership.viewed-seq." + ship) ?? ""

///|
extern "js" fn store_viewed(ship : String, viewed : String) -> Unit =
  #|(ship, viewed) => localStorage.setItem("brothership.viewed-seq." + ship, viewed)

///|
/// The player's running totals on `ship` as of the last time the screen
/// was open, as json, or "".
extern "js" fn load_ledger(ship : String) -> String =
  #|(ship) => localStorage.getItem("brothership.ledger." + ship) ?? ""

///|
extern "js" fn store_ledger(ship : String, ledger : String) -> Unit =
  #|(ship, ledger) => localStorage.setItem("brothership.ledger." + ship, ledger)

///|
/// The hours of the last watch chosen, or "".
extern "js" fn stored_watch() -> String =
  #|() => localStorage.getItem("brothership.watch") ?? ""

///|
extern "js" fn store_watch(hours : String) -> Unit =
  #|(hours) => localStorage.setItem("brothership.watch", hours)

///|
/// The address's fragment, with its `#`, or "".
extern "js" fn current_hash() -> String =
  #|() => location.hash

///|
/// What the player wants read aloud, as `Hear::name` gives it, or "".
extern "js" fn stored_hear() -> String =
  #|() => localStorage.getItem("brothership.hear") ?? ""

///|
extern "js" fn store_hear(hear : String) -> Unit =
  #|(hear) => localStorage.setItem("brothership.hear", hear)

///|
/// The ship this browser last boarded, or "".
extern "js" fn stored_ship() -> String =
  #|() => localStorage.getItem("brothership.ship") ?? ""

///|
extern "js" fn store_ship(ship : String) -> Unit =
  #|(ship) => localStorage.setItem("brothership.ship", ship)

///|
/// Move focus to the element with `id`, if the page has one.
extern "js" fn focus_id(id : String) -> Unit =
  #|(id) => document.getElementById(id)?.focus()

///|
extern "js" fn set_document_title(title : String) -> Unit =
  #|(title) => { document.title = title; }

///|
/// What the player wants played on happenings, as `Sounds::name` gives it,
/// or "".
extern "js" fn stored_sounds() -> String =
  #|() => localStorage.getItem("brothership.sounds") ?? ""

///|
extern "js" fn store_sounds(sounds : String) -> Unit =
  #|(sounds) => localStorage.setItem("brothership.sounds", sounds)

///|
/// The typeface chosen, as `Face::name` gives it, or "".
extern "js" fn stored_face() -> String =
  #|() => localStorage.getItem("brothership.face") ?? ""

///|
extern "js" fn store_face(face : String) -> Unit =
  #|(face) => localStorage.setItem("brothership.face", face)

///|
/// Set the page's typeface; the stylesheet keys on `data-face`.
extern "js" fn set_face(face : String) -> Unit =
  #|(face) => { document.documentElement.dataset.face = face; }

///|
/// Whether the browser has `document.ariaNotify`.
extern "js" fn has_aria_notify() -> Bool =
  #|() => typeof document.ariaNotify === "function"

///|
/// Speak `text` through the screen reader; `priority` is "normal" or "high".
extern "js" fn aria_notify(text : String, priority : String) -> Unit =
  #|(text, priority) => document.ariaNotify(text, { priority })

///|
/// Make the audio context, which a browser allows only after a gesture: now
/// if the page has been touched lately, otherwise at the next one.
extern "js" fn arm_sound() -> Unit =
  #|() => {
  #|  const make = () => {
  #|    const C = window.AudioContext || window.webkitAudioContext;
  #|    if (!C) return;
  #|    window.__tones ??= new C();
  #|    if (window.__tones.state === "suspended") window.__tones.resume();
  #|  };
  #|  if (window.__tones || navigator.userActivation?.isActive) make();
  #|  else for (const e of ["pointerdown", "keydown"]) addEventListener(e, make, { once: true });
  #|}

///|
/// Play a sine note on the armed context, with a 10 ms attack and a fade to
/// silence; does nothing before `arm_sound` has made it.
extern "js" fn play_note(
  hz : Double,
  at_ms : Double,
  ms : Double,
  gain : Double,
) -> Unit =
  #|(hz, at_ms, ms, gain) => {
  #|  const c = window.__tones;
  #|  if (!c || c.state !== "running") return;
  #|  const t = c.currentTime + at_ms / 1000, end = t + ms / 1000;
  #|  const o = c.createOscillator(), g = c.createGain();
  #|  o.frequency.value = hz;
  #|  g.gain.setValueAtTime(0.0001, t);
  #|  g.gain.linearRampToValueAtTime(gain, t + 0.01);
  #|  g.gain.exponentialRampToValueAtTime(0.0001, end);
  #|  o.connect(g).connect(c.destination);
  #|  o.start(t);
  #|  o.stop(end + 0.02);
  #|}
