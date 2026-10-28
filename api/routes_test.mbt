///|
async test "api round trip over http" {
  let store = @store.Store::open(":memory:", ship=@ships.profiles()[1], seed=1)
  defer store.close()
  store.advance(now=1_800_000_000)
  store.advance(now=1_800_000_600)
  let app = @moonback.App(@api.routes(store, clock=() => 1_800_000_660))
  defer app.close()
  let listener = @moonback.listen(host="127.0.0.1", port=0)
  let base = "http://127.0.0.1:\{listener.addr.port()}"
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => app.serve(listener))
    let (_, body) = @http.get("\{base}/api/snapshot")
    let snapshot : @core.Snapshot = @json.from_json(body.json())
    inspect(snapshot == store.snapshot(), content="true")
    let proposal : @core.Proposal = {
      id: 1,
      crew: "ann",
      intent: Posted(post=Hull),
    }
    let (_, body) = @http.post("\{base}/api/proposals", proposal.to_json())
    let receipt : @core.Receipt = @json.from_json(body.json())
    inspect(receipt is Accepted(id=1, ..), content="true")
    inspect(receipt.snapshot().state.at, content="1800000660")
    let (res, body) = @http.post("\{base}/api/proposals", "{\"id\":")
    inspect(res.code, content="400")
    json_inspect(body.json(), content={ "error": "Unexpected end of file" })
  })
}

///|
async test "a proposal naming a server event is refused with 400" {
  let store = @store.Store::open(":memory:", ship=@ships.profiles()[1], seed=1)
  defer store.close()
  let app = @moonback.App(@api.routes(store, clock=() => 1_800_000_000))
  defer app.close()
  let listener = @moonback.listen(host="127.0.0.1", port=0)
  let base = "http://127.0.0.1:\{listener.addr.port()}"
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => app.serve(listener))
    let tick : Json = {
      "id": "1",
      "crew": "ann",
      "intent": ["Tick", { "at": "9999999999" }],
    }
    let (res, _) = @http.post("\{base}/api/proposals", tick)
    inspect(res.code, content="400")
    inspect(store.snapshot().seq, content="0")
  })
}
