///|
/// Server-authoritative state after the event at log position `seq`.
/// `seq` is 0 for the empty log.
pub(all) struct Snapshot {
  seq : Int64
  state : State
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Snapshot::initial() -> Snapshot {
  { seq: 0, state: State::initial(), }
}

///|
/// A client's request to append `event`. `id` is assigned by the client and
/// only identifies the proposal within that client's session.
pub(all) struct Proposal {
  id : Int64
  event : Event
} derive(Debug, Eq, ToJson, FromJson)

///|
/// The server's answer to one `Proposal`. Both cases carry the server's
/// current snapshot so the client always settles to authoritative state.
pub(all) enum Receipt {
  Accepted(id~ : Int64, snapshot~ : Snapshot)
  Refused(id~ : Int64, reason~ : Rejected, snapshot~ : Snapshot)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Receipt::id(self : Receipt) -> Int64 {
  match self {
    Accepted(id~, ..) | Refused(id~, ..) => id
  }
}

///|
pub fn Receipt::snapshot(self : Receipt) -> Snapshot {
  match self {
    Accepted(snapshot~, ..) | Refused(snapshot~, ..) => snapshot
  }
}
