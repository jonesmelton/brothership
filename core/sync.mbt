///|
/// Client-side view of the game: the last snapshot confirmed by the server
/// plus proposals the server has not answered yet, oldest first.
///
/// The client sends `pending[0]` and waits for its receipt before sending the
/// next, so every receipt's snapshot includes all earlier proposals from this
/// client and none of the later ones. That ordering is what makes `settle`
/// sound; sending proposals concurrently would double-apply some of them.
pub struct Optimistic {
  confirmed : Snapshot
  pending : Array[Proposal]
  next_id : Int64
} derive(Debug, Eq)

///|
pub fn Optimistic::new(confirmed : Snapshot) -> Optimistic {
  { confirmed, pending: [], next_id: 1, }
}

///|
pub fn Optimistic::confirmed(self : Optimistic) -> Snapshot {
  self.confirmed
}

///|
/// The proposal awaiting a receipt, if any. Send it whenever this changes.
pub fn Optimistic::in_flight(self : Optimistic) -> Proposal? {
  self.pending.get(0)
}

///|
/// Confirmed state with pending proposals applied on top. Proposals that no
/// longer apply to the newer confirmed state are skipped; the server will
/// refuse them.
pub fn Optimistic::predicted(self : Optimistic) -> State {
  self.pending.fold(init=self.confirmed.state, (state, proposal) => {
    state.apply(proposal.event) catch {
      _ => state
    }
  })
}

///|
/// Queue `event` if it applies to the predicted state.
pub fn Optimistic::propose(
  self : Optimistic,
  event : Event,
) -> (Optimistic, Proposal) raise Rejected {
  ignore(self.predicted().apply(event))
  let proposal = { id: self.next_id, event, }
  let next = {
    confirmed: self.confirmed,
    pending: [..self.pending, proposal],
    next_id: self.next_id + 1,
  }
  (next, proposal)
}

///|
/// Adopt the server's answer to the in-flight proposal. Accepted or refused,
/// the proposal leaves the queue and the receipt's snapshot becomes the
/// confirmed state.
pub fn Optimistic::settle(self : Optimistic, receipt : Receipt) -> Optimistic {
  let snapshot = receipt.snapshot()
  {
    confirmed: if snapshot.seq >= self.confirmed.seq {
      snapshot
    } else {
      self.confirmed
    },
    pending: self.pending.filter(p => p.id > receipt.id()),
    next_id: self.next_id,
  }
}

///|
/// Adopt a snapshot obtained outside a receipt, such as on load or from a
/// poll. Ignored while a proposal is in flight, because the snapshot may or
/// may not already include it; the receipt will carry a fresh one.
pub fn Optimistic::resync(self : Optimistic, snapshot : Snapshot) -> Optimistic {
  if self.pending.is_empty() && snapshot.seq > self.confirmed.seq {
    { ..self, confirmed: snapshot, }
  } else {
    self
  }
}
