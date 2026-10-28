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
  // Logs from before ships were commissioned no longer replay: they hold
  // client-sent `Elapsed` events. Kept aside, not dropped.
  "alter table event rename to event_legacy",
  (
    #|create table event (
    #|  seq         integer primary key,
    #|  ship        text    not null,
    #|  body        text    not null check (json_valid(body)),
    #|  recorded_at integer not null default (unixepoch())
    #|) strict
  ),
  // A player's session, outside the event log: the cookie token and the
  // crew id it acts as. Not replayed and not part of the game state.
  (
    #|create table session (
    #|  token      text primary key,
    #|  officer    text not null unique,
    #|  created_at integer not null
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
