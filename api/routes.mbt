///|
/// Whether `officer` is aboard a ship other than `ship`. Such an officer gets
/// the fleet's whereabouts and no more of `ship`.
fn aboard_elsewhere(
  store : @store.Store,
  officer : String,
  ship : String,
) -> Bool {
  match store.aboard(officer) {
    Some(aboard) => aboard != ship
    None => false
  }
}

///|
/// Whether this request's session may read `ship`: it has no session, or its
/// officer is not aboard another ship.
async fn may_read(
  store : @store.Store,
  req : @moonback.Request,
  ship : String,
) -> Bool {
  match officer_of(store, req) {
    Some(officer) => !aboard_elsewhere(store, officer, ship)
    None => true
  }
}

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
/// An unknown ship is a 404. A session whose officer is aboard another ship
/// gets a 403 from that ship's snapshot and story: the fleet list is all it
/// may see of a ship it is not aboard. `clock` gives the wall clock in Unix
/// seconds; proposals are applied at it. `speaking` says whether a ship is
/// writing a line now, and `thinking` whether its mind is weighing a choice.
/// A proposal acts as the officer in its session cookie: no session is a
/// 401, and a proposal naming another officer, or a ship other than the one
/// the officer is aboard, is a 403.
/// `secure` marks the session cookie `Secure`; keep it false only for
/// plain-http development. A request with no session mints one only if
/// `mint_each` has a token for its client and `mint_all` has one for the
/// server; otherwise it is a 429 with `Retry-After`.
///
/// `GET /admin` is an HTML page of the whole game, with every ship's
/// officers, lines, log and `thoughts`, which players never see. It asks
/// for HTTP basic credentials matching `admin`, and is a 404 when `admin`
/// is `None`.

///|
pub fn routes(
  store : @store.Store,
  clock~ : () -> Int64 = unix_now,
  speaking~ : (String) -> Bool = _ => false,
  thinking~ : (String) -> Bool = _ => false,
  thoughts~ : (String) -> Array[String] = _ => [],
  admin~ : (String, String)? = None,
  secure~ : Bool = true,
  mint_each~ : Limiter = Limiter::new(burst=10, interval=30),
  mint_all~ : Limiter = Limiter::new(burst=200, interval=1),
) -> @moonback.Module {
  ctx => {
    ctx.get("/api/session", (req, res) => {
      let (officer, token) = match officer_of(store, req) {
        Some(officer) => (officer, None)
        None => {
          let wait = mint_each.take(client_of(req), now=clock())
          let wait = if wait > 0L {
            wait
          } else {
            mint_all.take("", now=clock())
          }
          if wait > 0L {
            res.send_json({ "error": "too many new sessions" }, status=429, headers=[
              ("Retry-After", wait.to_string()),
              ("Cache-Control", "no-store"),
            ])
            return
          }
          let token = new_token()
          let officer = new_officer()
          store.open_session(token, officer, now=clock())
          (officer, Some(token))
        }
      }
      let body : @core.Session = { officer, ship: store.aboard(officer), }
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
      guard may_read(store, req, ship) else {
        res.send_json({ "error": "aboard another ship" }, status=403)
        return
      }
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
    ctx.get("/admin", (req, res) => {
      guard admin is Some((user, password)) else {
        res.send_json({ "error": "no such page" }, status=404)
        return
      }
      guard admin_authorized(req, user, password) else {
        res.send_text("credentials required", status=401, headers=[
          (
            "WWW-Authenticate",
            "Basic realm=\"\{ADMIN_REALM}\", charset=\"UTF-8\"",
          ),
          ("Cache-Control", "no-store"),
        ])
        return
      }
      let page = admin_page(store, now=clock(), speaking~, thinking~, thoughts~)
      res.send_html(page, headers=[("Cache-Control", "no-store")])
    })
    ctx.get("/api/ships", (_req, res) => {
      let listings : Array[@core.Listing] = store
        .ships()
        .map(id => @ships.listing(id, store.snapshot(id).unwrap().state))
      res.send_json(Json(listings))
    })
    ctx.get("/api/ships/:id/snapshot", (req, res) => {
      let ship = req.params["id"].to_owned()
      guard may_read(store, req, ship) else {
        res.send_json({ "error": "aboard another ship" }, status=403)
        return
      }
      match store.snapshot(ship) {
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
        Some(officer) => {
          let ship = req.params["id"].to_owned()
          guard store.snapshot(ship) is Some(_) else {
            res.send_json({ "error": "no such ship" }, status=404)
            return
          }
          guard !aboard_elsewhere(store, officer, ship) else {
            res.send_json({ "error": "aboard another ship" }, status=403)
            return
          }
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
