///|
/// A direction for a ship to speak of, from whoever runs the game. Kept
/// beside the event log, not in it: players never see the text, only the
/// line the ship says in answer.
pub(all) struct Hail {
  id : Int64
  ship : String
  text : String
  /// Unix seconds.
  sent_at : Int64
  outcome : Outcome
} derive(Debug, Eq)

///|
/// What came of a hail.
pub(all) enum Outcome {
  /// The ship has not answered yet.
  Open
  /// The ship answered with the line at log position `seq`, at `at`.
  Spoke(seq~ : Int64, at~ : Int64)
  /// The ship said nothing, for `reason`: the model passed or failed, or
  /// the line was unusable, repeated or blocked.
  Silent(reason~ : String, at~ : Int64)
} derive(Debug, Eq)

///|
/// Send `text` to `ship` at `now`, in Unix seconds, and return the hail's
/// id, or `None` for an unknown ship.
pub async fn Store::hail(
  self : Store,
  ship : String,
  text : String,
  now~ : Int64,
) -> Int64? {
  self.write.acquire()
  defer self.write.release()
  guard self.voyages.contains(ship) else { return None }
  let stmt = self.conn.prepare_async(
    (
      #|insert into hail (ship, text, sent_at)
      #|values (?, ?, ?)
      #|returning id
    ),
  )
  defer stmt.finalize()
  stmt.bind(index=1, ship)
  stmt.bind(index=2, text)
  stmt.bind(index=3, now)
  guard stmt.step_async() is Row else { fail("insert returned no id") }
  let id : Int64 = stmt.column(index=0)
  while stmt.step_async() is Row {

  }
  Some(id)
}

///|
const HAIL_COLUMNS : String = "id, ship, text, sent_at, answered_at, spoke, silence"

///|
fn hail_of(stmt : @sqlite3.Statement) -> Hail raise {
  let answered_at : @sqlite3.Value = stmt.column(index=4)
  let spoke : @sqlite3.Value = stmt.column(index=5)
  let silence : @sqlite3.Value = stmt.column(index=6)
  let outcome = match (answered_at, spoke, silence) {
    (Integer(at), Integer(seq), _) => Spoke(seq~, at~)
    (Integer(at), _, Text(reason)) => Silent(reason~, at~)
    (Integer(at), _, _) => Silent(reason="", at~)
    _ => Open
  }
  {
    id: stmt.column(index=0),
    ship: stmt.column(index=1),
    text: stmt.column(index=2),
    sent_at: stmt.column(index=3),
    outcome,
  }
}

///|
/// `ship`'s unanswered hails, oldest first.
pub async fn Store::open_hails(self : Store, ship : String) -> Array[Hail] {
  self.write.acquire()
  defer self.write.release()
  let stmt = self.conn.prepare_async(
    (
      $|select \{HAIL_COLUMNS}
      $|  from hail
      $| where ship = ?
      $|   and answered_at is null
      $| order by id
    ),
  )
  defer stmt.finalize()
  stmt.bind(index=1, ship)
  let out = []
  while stmt.step_async() is Row {
    out.push(hail_of(stmt))
  }
  out
}

///|
/// Every hail to every ship, newest first.
pub async fn Store::hails(self : Store) -> Array[Hail] {
  self.write.acquire()
  defer self.write.release()
  let stmt = self.conn.prepare_async(
    (
      $|select \{HAIL_COLUMNS}
      $|  from hail
      $| order by id desc
    ),
  )
  defer stmt.finalize()
  let out = []
  while stmt.step_async() is Row {
    out.push(hail_of(stmt))
  }
  out
}

///|
/// Record that hail `id` came to nothing, for `reason`, at `now`. A hail
/// already answered keeps its answer.
pub async fn Store::silence(
  self : Store,
  id : Int64,
  reason~ : String,
  now~ : Int64,
) -> Unit {
  self.write.acquire()
  defer self.write.release()
  let stmt = self.conn.prepare_async(
    (
      #|update hail
      #|   set answered_at = ?,
      #|       silence     = ?
      #| where id = ?
      #|   and answered_at is null
    ),
  )
  defer stmt.finalize()
  stmt.bind(index=1, now)
  stmt.bind(index=2, reason)
  stmt.bind(index=3, id)
  while stmt.step_async() is Row {

  }
}

///|
/// Within `commit`'s transaction: hail `id` was answered at `now` by the
/// line at `seq`.
async fn Store::answered(
  self : Store,
  id : Int64,
  seq~ : Int64,
  now~ : Int64,
) -> Unit {
  let stmt = self.conn.prepare_async(
    (
      #|update hail
      #|   set answered_at = ?,
      #|       spoke       = ?
      #| where id = ?
      #|   and answered_at is null
    ),
  )
  defer stmt.finalize()
  stmt.bind(index=1, now)
  stmt.bind(index=2, seq)
  stmt.bind(index=3, id)
  while stmt.step_async() is Row {

  }
}
