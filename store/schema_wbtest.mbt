///|
async test "a v1 log is kept aside as event_legacy" {
  let conn = @sqlite3.Connection::open_async(":memory:")
  exec(conn, migrations[0])
  exec(conn, "pragma user_version = 1")
  exec(
    conn, "insert into event (body) values ('[\"Elapsed\",{\"ticks\":\"1\"}]')",
  )
  migrate(conn)
  inspect(query_int(conn, "pragma user_version"), content="6")
  inspect(query_int(conn, "select count(*) from event_legacy"), content="1")
  inspect(query_int(conn, "select count(*) from event"), content="0")
  conn.close()
}

///|
async test "a log from before banking is kept aside as event_before_banking" {
  let conn = @sqlite3.Connection::open_async(":memory:")
  for i in 0..<4 {
    exec(conn, migrations[i])
  }
  exec(conn, "pragma user_version = 4")
  exec(conn, "insert into event (ship, body) values ('ef-147', '[\"Docked\"]')")
  exec(
    conn, "insert into session (token, officer, created_at) values ('t', 'o', 0)",
  )
  migrate(conn)
  inspect(query_int(conn, "pragma user_version"), content="6")
  inspect(
    query_int(conn, "select count(*) from event_before_banking"),
    content="1",
  )
  inspect(query_int(conn, "select count(*) from event"), content="0")
  inspect(query_int(conn, "select count(*) from session"), content="1")
  conn.close()
}
