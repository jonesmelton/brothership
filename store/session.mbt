///|
/// The officer a session token acts as, or `None` if the token is unknown.
pub async fn Store::session(self : Store, token : String) -> String? {
  self.write.acquire()
  defer self.write.release()
  let stmt = self.conn.prepare_async(
    (
      #|select officer
      #|  from session
      #| where token = ?
    ),
  )
  defer stmt.finalize()
  stmt.bind(index=1, token)
  guard stmt.step_async() is Row else { return None }
  let officer : String = stmt.column(index=0)
  Some(officer)
}

///|
/// Record `token` as `officer`'s session, created at `now` in Unix seconds.
/// Sessions live beside the event log, not in it.
pub async fn Store::open_session(
  self : Store,
  token : String,
  officer : String,
  now~ : Int64,
) -> Unit {
  self.write.acquire()
  defer self.write.release()
  let stmt = self.conn.prepare_async(
    (
      #|insert into session (token, officer, created_at)
      #|values (?, ?, ?)
    ),
  )
  defer stmt.finalize()
  stmt.bind(index=1, token)
  stmt.bind(index=2, officer)
  stmt.bind(index=3, now)
  while stmt.step_async() is Row {

  }
}

///|
/// Every officer with a session and when it was opened, in Unix seconds,
/// newest first.
pub async fn Store::officers(self : Store) -> Array[(String, Int64)] {
  self.write.acquire()
  defer self.write.release()
  let stmt = self.conn.prepare_async(
    (
      #|select officer, created_at
      #|  from session
      #| order by created_at desc, rowid desc
    ),
  )
  defer stmt.finalize()
  let out = []
  while stmt.step_async() is Row {
    let officer : String = stmt.column(index=0)
    let created_at : Int64 = stmt.column(index=1)
    out.push((officer, created_at))
  }
  out
}
