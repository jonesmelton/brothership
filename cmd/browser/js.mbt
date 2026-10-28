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
/// The state this browser last showed, as JSON, or "" on a first visit.
extern "js" fn load_seen() -> String =
  #|() => localStorage.getItem("brothership.seen") ?? ""

///|
extern "js" fn store_seen(json : String) -> Unit =
  #|(json) => localStorage.setItem("brothership.seen", json)
