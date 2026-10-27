///|
/// The authoritative event log. Every accepted event is a row in `event`;
/// the current snapshot is the log replayed through `@core.State::apply` and
/// is kept in memory after `open`.
pub struct Store {
  priv conn : @sqlite3.Connection
  priv write : @async.Mutex
  priv mut snapshot : @core.Snapshot
}

///|
/// Open (creating if needed) the database at `path`, migrate it, and replay
/// the log. Use `":memory:"` for a throwaway store.
pub async fn Store::open(path : String) -> Store {
  let conn = @sqlite3.Connection::open_async(path)
  exec(conn, "pragma journal_mode = wal")
  exec(conn, "pragma synchronous = normal")
  exec(conn, "pragma foreign_keys = on")
  migrate(conn)
  { conn, write: @async.Mutex(), snapshot: load(conn), }
}

///|
async fn load(conn : @sqlite3.Connection) -> @core.Snapshot {
  let stmt = conn.prepare_async(
    (
      #|select seq, body
      #|  from event
      #| order by seq
    ),
  )
  defer stmt.finalize()
  let mut snapshot = @core.Snapshot::initial()
  while stmt.step_async() is Row {
    let seq : Int64 = stmt.column(index=0)
    let body : String = stmt.column(index=1)
    let event : @core.Event = @json.from_json(@json.parse(body))
    snapshot = { seq, state: snapshot.state.apply(event), }
  }
  snapshot
}

///|
pub fn Store::snapshot(self : Store) -> @core.Snapshot {
  self.snapshot
}

///|
/// Validate the proposed event against the current state and, if it applies,
/// append it. Refusals are part of the protocol and come back as a receipt;
/// only storage failures raise. Proposals are serialized so validation always
/// sees the state the event will follow.
pub async fn Store::propose(
  self : Store,
  proposal : @core.Proposal,
) -> @core.Receipt {
  self.write.acquire()
  defer self.write.release()
  let state = self.snapshot.state.apply(proposal.event) catch {
    reason => return Refused(id=proposal.id, reason~, snapshot=self.snapshot)
  }
  let stmt = self.conn.prepare_async(
    (
      #|insert into event (body)
      #|values (?)
      #|returning seq
    ),
  )
  defer stmt.finalize()
  stmt.bind(index=1, proposal.event.to_json().stringify())
  guard stmt.step_async() is Row else { fail("insert returned no seq") }
  let seq : Int64 = stmt.column(index=0)
  // Drain so the insert completes before the in-memory snapshot moves.
  while stmt.step_async() is Row {

  }
  self.snapshot = { seq, state, }
  Accepted(id=proposal.id, snapshot=self.snapshot)
}

///|
pub fn Store::close(self : Store) -> Unit raise {
  self.conn.close()
}
