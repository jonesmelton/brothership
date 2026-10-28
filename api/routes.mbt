///|
/// JSON API over the store. Wire types are the ones in `@core`, so the
/// browser decodes exactly what the server encodes.
///
/// - `GET /healthz` -> `{"ok": true}`, the path `fly.toml` checks
/// - `GET /api/session` -> `@core.Session`, and sets the `session` cookie
/// - `GET /api/ships` -> `Array[@core.Listing]`, in order of commission
/// - `GET /api/ships/:id/snapshot` -> `@core.Snapshot`
/// - `POST /api/ships/:id/proposals` with `@core.Proposal` -> `@core.Receipt`
/// - `GET /api/ships/:id/story?after=seq` -> `@core.Story`
///
/// An unknown ship is a 404. `clock` gives the wall clock in Unix seconds;
/// proposals are applied at it. `speaking` says whether a ship is writing a
/// line now, and `thinking` whether its mind is weighing a choice. A proposal acts as the officer in its session cookie: no
/// session is a 401, and a proposal naming another officer is a 403.
/// `secure` marks the session cookie `Secure`; keep it false only for
/// plain-http development.
pub fn routes(
  store : @store.Store,
  clock~ : () -> Int64 = unix_now,
  speaking~ : (String) -> Bool = _ => false,
  thinking~ : (String) -> Bool = _ => false,
  secure~ : Bool = true,
) -> @moonback.Module {
  ctx => {
    ctx.get("/api/session", (req, res) => {
      let (officer, token) = match officer_of(store, req) {
        Some(officer) => (officer, None)
        None => {
          let token = new_token()
          let officer = new_officer()
          store.open_session(token, officer, now=clock())
          (officer, Some(token))
        }
      }
      let body : @core.Session = { officer, }
      let headers = match token {
        None => [("Cache-Control", "no-store")]
        Some(token) =>
          [
            ("Set-Cookie", session_cookie(token, secure~)),
            ("Cache-Control", "no-store"),
          ]
      }
      res.send_json(body.to_json(), headers~)
    })
    ctx.get("/api/ships/:id/story", (req, res) => {
      let ship = req.params["id"].to_owned()
      let after = @string.parse_int64(req.query().get("after").unwrap_or("0")) catch {
        _ => 0L
      }
      match store.story(ship, after~) {
        Some(entries) => {
          let story : @core.Story = {
            entries,
            speaking: speaking(ship),
            thinking: thinking(ship),
          }
          res.send_json(story.to_json())
        }
        None => res.send_json({ "error": "no such ship" }, status=404)
      }
    })
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
      match officer_of(store, req) {
        None => res.send_json({ "error": "no session" }, status=401)
        Some(officer) if proposal.crew != officer =>
          res.send_json(
            { "error": "proposal is for another officer" },
            status=403,
          )
        Some(_) => {
          let ship = req.params["id"].to_owned()
          match store.propose(ship, proposal, now=clock()) {
            Some(receipt) => res.send_json(receipt.to_json())
            None => res.send_json({ "error": "no such ship" }, status=404)
          }
        }
      }
    })
  }
}

///|
/// The wall clock in Unix seconds.
pub fn unix_now() -> Int64 {
  @async.now() / 1000L
}
