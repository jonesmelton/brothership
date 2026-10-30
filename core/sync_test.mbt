///|
/// Reference server: validate with the shared transition, bump `seq` on accept.
fn serve(
  server : @core.Snapshot,
  proposal : @core.Proposal,
) -> (@core.Snapshot, @core.Receipt) {
  try server.state.apply(proposal.event()) catch {
    reason => (server, Refused(id=proposal.id, reason~, snapshot=server))
  } noraise {
    state => {
      let next : @core.Snapshot = { seq: server.seq + 1, state, }
      (next, Accepted(id=proposal.id, snapshot=next))
    }
  }
}

///|
/// The server's clock appends a tick, bypassing this client.
fn interfere(server : @core.Snapshot, arg : Int64) -> @core.Snapshot {
  let at = server.state.at + fold64(arg, 7200L) + 1L
  try server.state.apply(Tick(at~)) catch {
    _ => server
  } noraise {
    state => { seq: server.seq + 1, state, }
  }
}

///|
/// An intent for this client's crew member, chosen by `arg`.
fn intent_of(arg : Int64) -> @core.Intent {
  match fold64(arg, 6L) {
    0L => Posted(post=Drive)
    1L => Posted(post=Hull)
    2L => Posted(post=Craft)
    3L => Watched(ticks=@core.HOUR)
    4L => Crafted(craft=Engineer)
    _ => Left
  }
}

///|
fn propose_all(
  client : @core.Optimistic,
  args : Array[Int64],
) -> @core.Optimistic {
  args.fold(init=client, (client, arg) => {
    (client.propose("me", intent_of(arg)) catch {
      _ => (client, { id: 0, crew: "me", intent: Left, })
    }).0
  })
}

///|
fn departed() -> @core.Snapshot {
  { seq: 2, state: underway(plan20(), ship()), }
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
test "uncontended: the prediction is what the server settles to" {
  @qc.quick_check_fn(args => {
    let server = departed()
    let client = propose_all(@core.Optimistic::new(server), args)
    let predicted = client.predicted()
    let (client, server) = drain(client, server)
    predicted == server.state &&
    client.predicted() == server.state &&
    client.in_flight() is None
  })
}

///|
test "contended: the client converges to the server after draining" {
  // Each element is (whether the clock ticks first, argument).
  @qc.quick_check_fn((steps : Array[(Bool, Int64)]) => {
    let mut server = departed()
    let mut client = @core.Optimistic::new(server)
    for step in steps {
      let (ticks, arg) = step
      if ticks {
        server = interfere(server, arg)
      } else {
        client = propose_all(client, [arg])
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
  let (client, _) = @core.Optimistic::new(departed()).propose(
    "me",
    Posted(post=Hull),
  )
  let stale = client.resync(interfere(departed(), 60))
  inspect(stale.confirmed() == departed(), content="true")
}

///|
test "law: in port, one tick of n seconds equals n ticks of one" {
  @qc.quick_check_fn((input : (Int64, Array[Int32], Int32, Int64)) => {
    let (stores, picks, hull, n) = input
    let posts : Array[@core.Post] = [Drive, Hull, Craft]
    let posts = picks.map(p => posts[(p % 3).abs()])
    let s = loading(fold64(stores, 50_000L), posts, hull=hull_of(hull))
    let n = fold64(n, 3000L) + 1L
    let whole = tick(s, n)
    let mut split = s
    for _ in 0L..<n {
      split = tick(split, 1)
    }
    whole == split
  })
}
