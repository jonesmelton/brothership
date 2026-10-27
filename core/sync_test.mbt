///|
/// Reference server: validate with the shared transition, bump `seq` on accept.
fn serve(
  server : @core.Snapshot,
  proposal : @core.Proposal,
) -> (@core.Snapshot, @core.Receipt) {
  try server.state.apply(proposal.event) catch {
    reason => (server, Refused(id=proposal.id, reason~, snapshot=server))
  } noraise {
    state => {
      let next : @core.Snapshot = { seq: server.seq + 1, state, }
      (next, Accepted(id=proposal.id, snapshot=next))
    }
  }
}

///|
/// Another writer appends directly, bypassing this client.
fn interfere(server : @core.Snapshot, ticks : Int64) -> @core.Snapshot {
  try server.state.apply(Elapsed(ticks~)) catch {
    _ => server
  } noraise {
    state => { seq: server.seq + 1, state, }
  }
}

///|
fn drain(
  client : @core.Optimistic,
  server : @core.Snapshot,
) -> (@core.Optimistic, @core.Snapshot) {
  for client = client, server = server {
    match client.in_flight() {
      None => break (client, server)
      Some(proposal) => {
        let (server, receipt) = serve(server, proposal)
        continue client.settle(receipt), server
      }
    }
  }
}

///|
fn propose_all(
  client : @core.Optimistic,
  ticks : Array[Int64],
) -> @core.Optimistic {
  ticks.fold(init=client, (client, ticks) => {
    (client.propose(Elapsed(ticks~)) catch {
      _ => (client, { id: 0, event: Elapsed(ticks~), })
    }).0
  })
}

///|
test "uncontended: the prediction is what the server settles to" {
  @qc.quick_check_fn(ticks => {
    let server = @core.Snapshot::initial()
    let client = propose_all(@core.Optimistic::new(server), ticks)
    let predicted = client.predicted()
    let (client, server) = drain(client, server)
    predicted == server.state &&
    client.predicted() == server.state &&
    client.in_flight() is None
  })
}

///|
test "contended: the client converges to the server after draining" {
  // Each element is (whether another writer acts first, ticks).
  @qc.quick_check_fn((steps : Array[(Bool, Int64)]) => {
    let mut server = @core.Snapshot::initial()
    let mut client = @core.Optimistic::new(server)
    for step in steps {
      let (other_writer, ticks) = step
      if other_writer {
        server = interfere(server, ticks)
      } else {
        client = propose_all(client, [ticks])
        if client.in_flight() is Some(proposal) {
          let (next, receipt) = serve(server, proposal)
          server = next
          client = client.settle(receipt)
        }
      }
    }
    let (client, server) = drain(client.resync(server), server)
    let client = client.resync(server)
    client.confirmed() == server && client.predicted() == server.state
  })
}

///|
test "resync is ignored while a proposal is in flight" {
  let (client, _) = @core.Optimistic::new(@core.Snapshot::initial()).propose(
    Elapsed(ticks=1),
  )
  let stale = client.resync({ seq: 7, state: { clock: 7, }, })
  debug_inspect(stale.confirmed(), content="{ seq: 0, state: { clock: 0 } }")
}
