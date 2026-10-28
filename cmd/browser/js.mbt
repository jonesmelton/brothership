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
