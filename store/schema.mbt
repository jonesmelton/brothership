///|
/// Forward-only migrations. Entry `i` moves the schema from
/// `user_version = i` to `i + 1`. Append; never edit a shipped entry.
let migrations : Array[String] = [
  (
    #|create table event (
    #|  seq         integer primary key,
    #|  body        text    not null check (json_valid(body)),
    #|  recorded_at integer not null default (unixepoch())
    #|) strict
  ),
]

///|
async fn migrate(conn : @sqlite3.Connection) -> Unit {
  let current = query_int(conn, "pragma user_version")
  for version in current..<migrations.length() {
    exec(conn, "begin immediate")
    errdefer exec(conn, "rollback")
    exec(conn, migrations[version])
    // pragma arguments cannot be bound; `version` is an Int, not input.
    exec(conn, "pragma user_version = \{version + 1}")
    exec(conn, "commit")
  }
}
