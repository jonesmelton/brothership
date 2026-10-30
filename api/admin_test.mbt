///|
/// Serve `store` with the admin page open to `admin:hunter2`, and run `f`
/// with its base URL.
async fn with_admin(
  store : @store.Store,
  now : Int64,
  f : async (String) -> Unit,
  admin~ : (String, String)? = Some(("admin", "hunter2")),
) -> Unit {
  let app = @moonback.App(
    @api.routes(
      store,
      clock=() => now,
      admin~,
      thoughts=ship => {
        if ship == "tigress" {
          ["<b>keep the hull</b>"]
        } else {
          []
        }
      },
      mint_each=@api.Limiter::new(burst=1000, interval=1),
    ),
  )
  defer app.close()
  let listener = @moonback.listen(host="127.0.0.1", port=0)
  let base = "http://127.0.0.1:\{listener.addr.port()}"
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => app.serve(listener))
    f(base)
  })
}

///|
fn basic(credentials : String) -> Map[@http.CaseInsensitiveString, String] {
  { "Authorization": "Basic \{credentials}" }
}

///|
async test "the admin page asks for credentials and refuses wrong ones" {
  let store = fleet_store()
  defer store.close()
  with_admin(store, 1_800_000_000, base => {
    let (res, _) = @http.get("\{base}/admin")
    inspect(res.code, content="401")
    debug_inspect(
      res.headers.get("WWW-Authenticate"),
      content=(
        #|Some("Basic realm=\"brothership admin\", charset=\"UTF-8\"")
      ),
    )
    let (res, _) = @http.get("\{base}/admin", headers=basic("YWRtaW46d3Jvbmc="))
    inspect(res.code, content="401")
    let (res, _) = @http.get("\{base}/admin", headers=basic("not base64!"))
    inspect(res.code, content="401")
  })
}

///|
async test "the admin page is not served without credentials configured" {
  let store = fleet_store()
  defer store.close()
  with_admin(store, 1_800_000_000, admin=None, base => {
    let (res, _) = @http.get(
      "\{base}/admin",
      headers=basic("YWRtaW46aHVudGVyMg=="),
    )
    inspect(res.code, content="404")
  })
}

///|
async test "the admin page shows every ship, officer and thought" {
  let store = fleet_store()
  defer store.close()
  store.advance("tigress", now=1_800_000_000)
  with_admin(store, 1_800_000_060, base => {
    let (cookie, session) = new_session(base)
    let proposal : @core.Proposal = {
      id: 1,
      crew: session.officer,
      intent: Posted(post=Hull),
    }
    let _ = @http.post(
      "\{base}/api/ships/tigress/proposals",
      proposal.to_json(),
      headers=cookie_header(cookie),
    )
    let (res, body) = @http.get(
      "\{base}/admin",
      headers=basic("YWRtaW46aHVudGVyMg=="),
    )
    inspect(res.code, content="200")
    debug_inspect(
      res.headers.get("Cache-Control"),
      content="Some(\"no-store\")",
    )
    let html = body.text()
    for berth in @ships.fleet() {
      let name = @ships.listing(
          berth.id,
          store.snapshot(berth.id).unwrap().state,
        ).name
      assert_true(html.contains(name), msg="missing \{name}")
    }
    assert_true(html.contains(session.officer))
    assert_true(html.contains("\{session.officer} signed on"))
    assert_true(html.contains("&lt;b&gt;keep the hull&lt;/b&gt;"))
  })
}
