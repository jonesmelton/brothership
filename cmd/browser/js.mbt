///|
/// The local wall clock in Unix seconds.
fn unix_now() -> Int64 {
  date_now_ms().to_int64() / 1000L
}

///|
extern "js" fn date_now_ms() -> Double = "() => Date.now()"

///|
/// This browser's crew id, made once and kept in `localStorage`. There are
/// no accounts yet, so anyone who sends an id acts as that crew member.
extern "js" fn crew_id() -> String =
  #|() => {
  #|  let id = localStorage.getItem("brothership.crew");
  #|  if (!id) {
  #|    id = "crew-" + crypto.randomUUID().slice(0, 8);
  #|    localStorage.setItem("brothership.crew", id);
  #|  }
  #|  return id;
  #|}

///|
/// The newest story `seq` this browser has shown of `ship`, or "" if none.
extern "js" fn load_seen(ship : String) -> String =
  #|(ship) => localStorage.getItem("brothership.seen-seq." + ship) ?? ""

///|
extern "js" fn store_seen(ship : String, seq : String) -> Unit =
  #|(ship, seq) => localStorage.setItem("brothership.seen-seq." + ship, seq)

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
