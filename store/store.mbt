///|
/// The authoritative event log of every ship. Every accepted event is a row
/// in `event` with the ship's id; each ship's snapshot is its rows replayed
/// from its `Commissioned`, and is kept in memory after `open`.
///
/// Only the store moves game time: it appends a tick at the wall clock it is
/// given before anything else it writes for a ship.
pub struct Store {
  priv conn : @sqlite3.Connection
  priv write : @async.Mutex
  /// By ship id, in order of commission.
  priv voyages : Map[String, Voyage]
}

///|
/// One ship's voyage: the profile it flies by, from its `Commissioned`, and
/// its snapshot. `seq` is the log position of the ship's latest row.
priv struct Voyage {
  profile : @ships.Profile
  mut snapshot : @core.Snapshot
  /// Every happening since commissioning, oldest first. Derived from the
  /// rows on open and on commit; never stored.
  story : Array[@core.Entry]
  /// The ship's mind makes its turn and chooses its promotions, and the
  /// clock leaves them out (see `Profile::due`). Set by `Store::mind`, not
  /// stored.
  mut minded : Bool
}

///|
/// Apply `event` to `state`, recording what it tells in `story`.
fn Voyage::tell(
  self : Voyage,
  state : @core.State,
  event : @core.Event,
  seq : Int64,
) -> @core.State raise @core.Rejected {
  let next = state.apply(event)
  for h in @core.happenings(state, event, next) {
    self.story.push({ seq, at: next.at, happening: h, })
  }
  next
}

///|
/// Open (creating if needed) the database at `path`, migrate it, and replay
/// the log. Use `":memory:"` for a throwaway store.
pub async fn Store::open(path : String) -> Store {
  let conn = @sqlite3.Connection::open_async(path)
  exec(conn, "pragma journal_mode = wal")
  // Litestream checkpoints the WAL on its own schedule and briefly holds a
  // lock; wait for it instead of failing a proposal with SQLITE_BUSY.
  exec(conn, "pragma busy_timeout = 5000")
  exec(conn, "pragma synchronous = normal")
  exec(conn, "pragma foreign_keys = on")
  migrate(conn)
  { conn, write: @async.Mutex(), voyages: load(conn), }
}

///|
fn voyage(state : @core.State) -> Voyage {
  guard @ships.profile_named(state.profile) is Some(profile) else {
    abort("no ship profile named \{state.profile}")
  }
  { profile, snapshot: { seq: 0, state, }, story: [], minded: false, }
}

///|
async fn load(conn : @sqlite3.Connection) -> Map[String, Voyage] {
  let stmt = conn.prepare_async(
    (
      #|select seq, ship, body
      #|  from event
      #| order by seq
    ),
  )
  defer stmt.finalize()
  let voyages : Map[String, Voyage] = Map([])
  while stmt.step_async() is Row {
    let seq : Int64 = stmt.column(index=0)
    let ship : String = stmt.column(index=1)
    let body : String = stmt.column(index=2)
    let event : @core.Event = @json.from_json(@json.parse(body))
    let v = match voyages.get(ship) {
      Some(v) => v
      None => {
        let v = voyage(@core.State::commission(event))
        voyages[ship] = v
        v.snapshot = { seq, state: v.snapshot.state, }
        continue
      }
    }
    v.snapshot = { seq, state: v.tell(v.snapshot.state, event, seq), }
  }
  voyages
}

///|
/// Ship ids, in order of commission.
pub fn Store::ships(self : Store) -> Array[String] {
  self.voyages.keys().collect()
}

///|
/// The ship's current snapshot, or `None` for an unknown ship.
pub fn Store::snapshot(self : Store, ship : String) -> @core.Snapshot? {
  self.voyages.get(ship).map(v => v.snapshot)
}

///|
/// Put `berth`'s ship into service, unless a ship with its id already is.
/// A ship's log begins with this, so its profile and seed are fixed here and
/// later changes to the berth affect only timing.
pub async fn Store::commission(self : Store, berth : @ships.Berth) -> Unit {
  self.write.acquire()
  defer self.write.release()
  guard !self.voyages.contains(berth.id) else { return }
  let event = berth.commission()
  let v = voyage(@core.State::commission(event))
  self.voyages[berth.id] = v
  self.commit(berth.id, v, [event], v.snapshot.state)
}

///|
/// Append `events`, which must apply in order to the current state, in one
/// transaction: all of them or none.
async fn Store::commit(
  self : Store,
  ship : String,
  v : Voyage,
  events : Array[@core.Event],
  state : @core.State,
) -> Unit {
  guard !events.is_empty() else { return }
  exec(self.conn, "begin immediate")
  errdefer exec(self.conn, "rollback")
  let stmt = self.conn.prepare_async(
    (
      #|insert into event (ship, body)
      #|values (?, ?)
      #|returning seq
    ),
  )
  defer stmt.finalize()
  let mut seq = v.snapshot.seq
  let seqs = []
  for event in events {
    stmt.reset()
    stmt.bind(index=1, ship)
    stmt.bind(index=2, event.to_json().stringify())
    guard stmt.step_async() is Row else { fail("insert returned no seq") }
    seq = stmt.column(index=0)
    // Drain so the insert completes before the next.
    while stmt.step_async() is Row {

    }
    seqs.push(seq)
  }
  exec(self.conn, "commit")
  // `Commissioned` begins the state rather than applying to it.
  let mut s = v.snapshot.state
  for i, event in events {
    guard !(event is Commissioned(_)) else { continue }
    s = v.tell(s, event, seqs[i]) catch {
      err =>
        abort("store: committed event refused: \{err.to_json().stringify()}")
    }
  }
  v.snapshot = { seq, state, }
}

///|
/// Validate the proposal for `ship` against its state at `now`, in Unix
/// seconds, and, if it applies, append it. The ship's own events at `now` go
/// first and are appended either way; its response to the proposal follows
/// it. Refusals are part of the protocol and come back as a receipt; only
/// storage failures raise. `None` for an unknown ship. Writes are serialized
/// so validation always sees the state the event will follow.
pub async fn Store::propose(
  self : Store,
  ship : String,
  proposal : @core.Proposal,
  now~ : Int64,
) -> @core.Receipt? {
  self.write.acquire()
  defer self.write.release()
  guard self.voyages.get(ship) is Some(v) else { return None }
  let (due, state) = v.profile.due(
    v.snapshot.state,
    now,
    officer=_ => true,
    minded=v.minded,
  )
  let accepted = state.apply(proposal.event()) catch {
    reason => {
      self.commit(ship, v, due, state)
      return Some(Refused(id=proposal.id, reason~, snapshot=v.snapshot))
    }
  }
  let (response, state) = v.profile.respond(accepted, minded=v.minded)
  self.commit(ship, v, [..due, proposal.event(), ..response], state)
  Some(Accepted(id=proposal.id, snapshot=v.snapshot))
}

///|
/// Append what `ship` does at `now`, in Unix seconds: the tick, docking,
/// departure and its turn. Does nothing for an unknown ship.
pub async fn Store::advance(self : Store, ship : String, now~ : Int64) -> Unit {
  self.write.acquire()
  defer self.write.release()
  guard self.voyages.get(ship) is Some(v) else { return }
  let (due, state) = v.profile.due(
    v.snapshot.state,
    now,
    officer=_ => true,
    minded=v.minded,
  )
  self.commit(ship, v, due, state)
}

///|
/// The ship's happenings after log position `after`, oldest first, or
/// `None` for an unknown ship.
pub fn Store::story(
  self : Store,
  ship : String,
  after~ : Int64,
) -> Array[@core.Entry]? {
  self.voyages
  .get(ship)
  .map(v => v.story.iter().filter(e => e.seq > after).collect())
}

///|
/// Append the ship's line `line`, answering the happening at `about`, after
/// the ship's own events at `now`. Does nothing for an unknown ship. The
/// line is shown to players, so it must have passed the gate.
pub async fn Store::speak(
  self : Store,
  ship : String,
  line~ : @llm_gate.Cleared,
  about~ : Int64,
  now~ : Int64,
) -> Unit {
  self.write.acquire()
  defer self.write.release()
  guard self.voyages.get(ship) is Some(v) else { return }
  let (due, state) = v.profile.due(
    v.snapshot.state,
    now,
    officer=_ => true,
    minded=v.minded,
  )
  let spoke : @core.Event = Spoke(line=line.text(), about~)
  self.commit(ship, v, [..due, spoke], state)
}

///|
/// Leave `ship`'s turn and promotions to its mind from now on, which acts
/// through `decide` and `muster`. Lasts until the store closes.
pub fn Store::mind(self : Store, ship : String) -> Unit {
  if self.voyages.get(ship) is Some(v) {
    v.minded = true
  }
}

///|
/// Whether `ship`'s mind takes its turn.
pub fn Store::minded(self : Store, ship : String) -> Bool {
  self.voyages.get(ship).map(v => v.minded).unwrap_or(false)
}

///|
/// Append the turn `acts` that `ship`'s mind chose at `moment`, after the
/// ship's own events at `now`. Nothing of the turn is appended if the ship
/// is no longer underway at that moment, since the mind weighed another;
/// an act that no longer applies, such as an unbuildable refit, is dropped.
/// Returns whether the turn was taken.
pub async fn Store::decide(
  self : Store,
  ship : String,
  acts : Array[@ships.Act],
  moment~ : @core.Moment,
  now~ : Int64,
) -> Bool {
  self.write.acquire()
  defer self.write.release()
  guard self.voyages.get(ship) is Some(v) else { return false }
  let (due, state) = v.profile.due(
    v.snapshot.state,
    now,
    officer=_ => true,
    minded=v.minded,
  )
  guard state.crossing() is Some(c) &&
    c.arrived_at is None &&
    c.moment() == moment else {
    self.commit(ship, v, due, state)
    return false
  }
  let events = [..due]
  let mut s = state
  for act in acts {
    let e = act.event()
    s = s.apply(e) catch { _ => continue }
    events.push(e)
  }
  self.commit(ship, v, events, s)
  true
}

///|
/// Append the promotions `ship`'s mind chose from `picks`, in order, that
/// `@ships.allowed` lets stand, then dock, after the ship's own events at
/// `now`. Returns the promotions appended, as (crew, new rank), or `None`
/// if the ship is not arrived and waiting to dock.
pub async fn Store::muster(
  self : Store,
  ship : String,
  picks : Array[String],
  now~ : Int64,
) -> Array[(String, Int64)]? {
  self.write.acquire()
  defer self.write.release()
  guard self.voyages.get(ship) is Some(v) else { return None }
  let (due, state) = v.profile.due(
    v.snapshot.state,
    now,
    officer=_ => true,
    minded=v.minded,
  )
  guard state.crossing() is Some(c) && c.arrived_at is Some(_) else {
    self.commit(ship, v, due, state)
    return None
  }
  let promoted = @ships.allowed(c, picks, officer=_ => true)
  let events = [..due]
  let mut s = state
  for pair in promoted {
    let e : @core.Event = Promoted(crew=pair.0, rank=pair.1)
    s = s.apply(e) catch {
      err =>
        abort("store: allowed promotion refused: \{err.to_json().stringify()}")
    }
    events.push(e)
  }
  s = s.apply(Docked) catch {
    err => abort("store: docking refused: \{err.to_json().stringify()}")
  }
  events.push(Docked)
  self.commit(ship, v, events, s)
  Some(promoted)
}

///|
pub fn Store::close(self : Store) -> Unit raise {
  self.conn.close()
}
