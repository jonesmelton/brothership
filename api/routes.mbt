///|
/// JSON API over the store. Wire types are the ones in `@core`, so the
/// browser decodes exactly what the server encodes.
///
/// - `GET /api/snapshot` -> `@core.Snapshot`
/// - `POST /api/proposals` with `@core.Proposal` -> `@core.Receipt`
pub fn routes(store : @store.Store) -> @moonback.Module {
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
      res.send_json(store.propose(proposal).to_json())
    })
  }
}
