///|
async test "a v1 log is kept aside as event_legacy" {
  let conn = @sqlite3.Connection::open_async(":memory:")
  exec(conn, migrations[0])
  exec(conn, "pragma user_version = 1")
  exec(
    conn, "insert into event (body) values ('[\"Elapsed\",{\"ticks\":\"1\"}]')",
  )
  migrate(conn)
  inspect(query_int(conn, "pragma user_version"), content="3")
  inspect(query_int(conn, "select count(*) from event_legacy"), content="1")
  inspect(query_int(conn, "select count(*) from event"), content="0")
  conn.close()
}
