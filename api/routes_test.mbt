///|
async test "api round trip over http" {
  let store = @store.Store::open(":memory:")
  defer store.close()
  let app = @moonback.App(@api.routes(store))
  defer app.close()
  let listener = @moonback.listen(host="127.0.0.1", port=0)
  let base = "http://127.0.0.1:\{listener.addr.port()}"
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => app.serve(listener))
    let (_, body) = @http.get("\{base}/api/snapshot")
    json_inspect(body.json(), content={ "seq": "0", "state": { "clock": "0" } })
    let proposal : @core.Proposal = { id: 1, event: Elapsed(ticks=2), }
    let (_, body) = @http.post("\{base}/api/proposals", proposal.to_json())
    json_inspect(body.json(), content=[
      "Accepted",
      { "id": "1", "snapshot": { "seq": "1", "state": { "clock": "2" } } },
    ])
    let (res, body) = @http.post("\{base}/api/proposals", "{\"id\":")
    inspect(
      res.code,
      content=(
        #|400
      ),
    )
    json_inspect(body.json(), content={ "error": "Unexpected end of file" })
  })
}
