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
/// The server refuses a `crew` that is not the officer its session names.
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
/// `GET /api/session`: the officer this client acts as. The session token
/// stays in an HttpOnly cookie; the body carries only the public crew id.
pub(all) struct Session {
  officer : String
  /// The ship the officer is aboard; `None` until they sign on, and again
  /// once discharged.
  ship : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Where a ship in a `Listing` is, in Unix seconds.
pub(all) enum Whereabouts {
  /// In port, leaving at `departs`.
  InPort(departs~ : Int64)
  /// Underway, arriving at `arrives` if no one changes post, or arrived
  /// if that is past; `None` if too far off to forecast.
  Underway(arrives~ : Int64?)
} derive(Debug, Eq, ToJson, FromJson)

///|
/// One ship in `GET /api/ships`.
pub(all) struct Listing {
  id : String
  /// The profile's name, which is the ship's name in English.
  name : String
  /// Crossings flown; `@ships.leg` names the worlds of the one in hand.
  crossings : Int64
  whereabouts : Whereabouts
  /// How much of the leg is behind the ship, in thousandths: 0 in port and
  /// 1000 once arrived. Enough to place it on the star map and no more.
  run : Int64
  /// Officers aboard.
  officers : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// One happening in a ship's story: the log position of the row it came
/// from, and the game time then, in Unix seconds.
pub(all) struct Entry {
  seq : Int64
  at : Int64
  happening : Happening
} derive(Debug, Eq, ToJson, FromJson)

///|
/// `GET /api/ships/:id/story`: the entries after the asked-for `seq`, oldest
/// first, whether the ship is writing a line now, and whether it is
/// weighing a choice.
pub(all) struct Story {
  entries : Array[Entry]
  speaking : Bool
  /// The ship's mind is weighing a choice now.
  thinking : Bool
} derive(Debug, Eq, ToJson, FromJson)
