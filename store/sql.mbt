///|
/// Run one statement that returns no rows of interest.
async fn exec(conn : @sqlite3.Connection, sql : String) -> Unit {
  let stmt = conn.prepare_async(sql)
  defer stmt.finalize()
  while stmt.step_async() is Row {

  }
}

///|
/// Run a query whose first row's first column is an integer.
async fn query_int(conn : @sqlite3.Connection, sql : String) -> Int32 {
  let stmt = conn.prepare_async(sql)
  defer stmt.finalize()
  guard stmt.step_async() is Row else { fail("no row from: \{sql}") }
  let value : Int64 = stmt.column(index=0)
  value.to_int()
}
