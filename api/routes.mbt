///|
/// JSON API over the store. Wire types are the ones in `@core`, so the
/// browser decodes exactly what the server encodes.
///
/// - `GET /healthz` -> `{"ok": true}`, the path `fly.toml` checks
/// - `GET /api/ships` -> `Array[@core.Listing]`, in order of commission
/// - `GET /api/ships/:id/snapshot` -> `@core.Snapshot`
/// - `POST /api/ships/:id/proposals` with `@core.Proposal` -> `@core.Receipt`
///
/// An unknown ship is a 404. `clock` gives the wall clock in Unix seconds;
/// proposals are applied at it.
pub fn routes(
  store : @store.Store,
  clock~ : () -> Int64 = unix_now,
) -> @moonback.Module {
  ctx => {
    // The listener binds only after the store opens and commissions its
    // ships, so answering at all proves boot got that far. Keep this free of
    // the game API's routes: Fly takes the whole machine out of rotation when
    // its check fails.
    ctx.get("/healthz", (_req, res) => res.send_json({ "ok": true }))
    ctx.get("/api/ships", (_req, res) => {
      let listings : Array[@core.Listing] = store
        .ships()
        .map(id => { id, name: store.snapshot(id).unwrap().state.profile, })
      res.send_json(Json(listings))
    })
    ctx.get("/api/ships/:id/snapshot", (req, res) => {
      match store.snapshot(req.params["id"].to_owned()) {
        Some(snapshot) => res.send_json(snapshot.to_json())
        None => res.send_json({ "error": "no such ship" }, status=404)
      }
    })
    ctx.post("/api/ships/:id/proposals", (req, res) => {
      let proposal : @core.Proposal = @json.from_json(req.body.json()) catch {
        err => {
          res.send_json({ "error": err.to_string() }, status=400)
          return
        }
      }
      let ship = req.params["id"].to_owned()
      match store.propose(ship, proposal, now=clock()) {
        Some(receipt) => res.send_json(receipt.to_json())
        None => res.send_json({ "error": "no such ship" }, status=404)
      }
    })
  }
}

///|
/// The wall clock in Unix seconds.
pub fn unix_now() -> Int64 {
  @async.now() / 1000L
}
