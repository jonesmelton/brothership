///|
/// JSON API over the store. Wire types are the ones in `@core`, so the
/// browser decodes exactly what the server encodes.
///
/// - `GET /api/snapshot` -> `@core.Snapshot`
/// - `POST /api/proposals` with `@core.Proposal` -> `@core.Receipt`
///
/// `clock` gives the wall clock in Unix seconds; proposals are applied at it.
pub fn routes(
  store : @store.Store,
  clock~ : () -> Int64 = unix_now,
) -> @moonback.Module {
  ctx => {
    ctx.get("/api/snapshot", (_req, res) => {
      res.send_json(store.snapshot().to_json())
    })
    ctx.post("/api/proposals", (req, res) => {
      let proposal : @core.Proposal = @json.from_json(req.body.json()) catch {
        err => {
          res.send_json({ "error": err.to_string() }, status=400)
          return
        }
      }
      res.send_json(store.propose(proposal, now=clock()).to_json())
    })
  }
}

///|
/// The wall clock in Unix seconds.
pub fn unix_now() -> Int64 {
  @async.now() / 1000L
}
