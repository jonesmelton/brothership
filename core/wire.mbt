///|
/// Server-authoritative state after the event at log position `seq`.
/// `seq` is 0 for the empty log.
pub(all) struct Snapshot {
  seq : Int64
  state : State
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A client's request for `crew` to do `intent`. `id` is assigned by the
/// client and only identifies the proposal within that client's session.
/// Nothing checks `crew`: until there are accounts, any client can act as
/// any crew member.
pub(all) struct Proposal {
  id : Int64
  crew : String
  intent : Intent
} derive(Debug, Eq, ToJson, FromJson)

///|
/// The event the proposal asks the server to append.
pub fn Proposal::event(self : Proposal) -> Event {
  Crew(crew=self.crew, intent=self.intent)
}

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

///|
/// One ship in `GET /api/ships`.
pub(all) struct Listing {
  id : String
  /// The profile's name, which is the ship's name in English.
  name : String
} derive(Debug, Eq, ToJson, FromJson)
