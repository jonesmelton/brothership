///|
/// The authoritative event log. Every accepted event is a row in `event`;
/// the current snapshot is the log replayed through `@core.State::apply` and
/// is kept in memory after `open`.
///
/// Only the store moves game time: it appends a tick at the wall clock it is
/// given before anything else it writes.
pub struct Store {
  priv conn : @sqlite3.Connection
  priv write : @async.Mutex
  priv ship : @ships.Profile
  priv mut snapshot : @core.Snapshot
}

///|
/// Open (creating if needed) the database at `path`, migrate it, and replay
/// the log. Use `":memory:"` for a throwaway store.
///
/// The log starts from `ship`'s profile with `seed`, so a database must
/// always be opened with the same ones.
pub async fn Store::open(
  path : String,
  ship~ : @ships.Profile,
  seed~ : Int64,
) -> Store {
  let conn = @sqlite3.Connection::open_async(path)
  exec(conn, "pragma journal_mode = wal")
  // Litestream checkpoints the WAL on its own schedule and briefly holds a
  // lock; wait for it instead of failing a proposal with SQLITE_BUSY.
  exec(conn, "pragma busy_timeout = 5000")
  exec(conn, "pragma synchronous = normal")
  exec(conn, "pragma foreign_keys = on")
  migrate(conn)
  let initial = @core.Snapshot::initial(ship.ship(seed~))
  { conn, write: @async.Mutex(), ship, snapshot: load(conn, initial), }
}

///|
async fn load(
  conn : @sqlite3.Connection,
  initial : @core.Snapshot,
) -> @core.Snapshot {
  let stmt = conn.prepare_async(
    (
      #|select seq, body
      #|  from event
      #| order by seq
    ),
  )
  defer stmt.finalize()
  let mut snapshot = initial
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
/// Append `events`, which must apply in order to the current state, in one
/// transaction: all of them or none.
async fn Store::commit(
  self : Store,
  events : Array[@core.Event],
  state : @core.State,
) -> Unit {
  guard !events.is_empty() else { return }
  exec(self.conn, "begin immediate")
  errdefer exec(self.conn, "rollback")
  let stmt = self.conn.prepare_async(
    (
      #|insert into event (body)
      #|values (?)
      #|returning seq
    ),
  )
  defer stmt.finalize()
  let mut seq = self.snapshot.seq
  for event in events {
    stmt.reset()
    stmt.bind(index=1, event.to_json().stringify())
    guard stmt.step_async() is Row else { fail("insert returned no seq") }
    seq = stmt.column(index=0)
    // Drain so the insert completes before the next.
    while stmt.step_async() is Row {

    }
  }
  exec(self.conn, "commit")
  self.snapshot = { seq, state, }
}

///|
/// Validate the proposal against the state at `now`, in Unix seconds, and,
/// if it applies, append it. The ship's own events at `now` go first and are
/// appended either way; its response to the proposal follows it. Refusals
/// are part of the protocol and come back as a receipt; only storage
/// failures raise. Proposals are serialized so validation always sees the
/// state the event will follow.
pub async fn Store::propose(
  self : Store,
  proposal : @core.Proposal,
  now~ : Int64,
) -> @core.Receipt {
  self.write.acquire()
  defer self.write.release()
  let (due, state) = self.ship.due(self.snapshot.state, now)
  let accepted = state.apply(proposal.event()) catch {
    reason => {
      self.commit(due, state)
      return Refused(id=proposal.id, reason~, snapshot=self.snapshot)
    }
  }
  let (response, state) = self.ship.respond(accepted)
  self.commit([..due, proposal.event(), ..response], state)
  Accepted(id=proposal.id, snapshot=self.snapshot)
}

///|
/// Append what the ship does at `now`, in Unix seconds: the tick, docking,
/// departure and its turn.
pub async fn Store::advance(self : Store, now~ : Int64) -> Unit {
  self.write.acquire()
  defer self.write.release()
  let (due, state) = self.ship.due(self.snapshot.state, now)
  self.commit(due, state)
}

///|
/// The next instant, in Unix seconds, at which the ship has something to do.
pub fn Store::wake(self : Store) -> Int64 {
  self.ship.wake(self.snapshot.state)
}

///|
pub fn Store::close(self : Store) -> Unit raise {
  self.conn.close()
}
