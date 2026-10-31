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

///|
fn admin_headers(
  extra : Array[(String, String)],
) -> Map[@http.CaseInsensitiveString, String] {
  let headers = basic("YWRtaW46aHVudGVyMg==")
  for pair in extra {
    headers[pair.0] = pair.1
  }
  headers
}

///|
async test "hails are sent as json to the ships named, and refused whole if any is wrong" {
  let store = fleet_store()
  defer store.close()
  with_admin(store, 1_800_000_000, base => {
    let hail : Json = {
      "ships": ["tigress", "scorpion"],
      "text": "Dust ahead.",
    }
    let (res, _) = @http.post("\{base}/admin/hails", hail)
    inspect(res.code, content="401")
    let (res, body) = @http.post(
      "\{base}/admin/hails",
      hail,
      headers=admin_headers([]),
    )
    inspect(
      res.code,
      content=(
        #|400
      ),
    )
    json_inspect(body.json(), content={
      "error": "ship does not speak: tigress",
    })
    for
      bad in [
        ({ "ships": ["tigress", "nobody"], "text": "Dust ahead." } : Json),
        { "ships": ["tigress"], "text": "  " },
        { "ships": [], "text": "Dust ahead." },
        { "ships": ["flea"], "text": "Dust ahead." },
        { "text": "Dust ahead." },
      ] {
      let (res, _) = @http.post(
        "\{base}/admin/hails",
        bad,
        headers=admin_headers([]),
      )
      inspect(res.code, content="400")
    }
    inspect(
      store.hails().length(),
      content=(
        #|0
      ),
    )
  })
}

///|
async test "the admin page's form sends hails, but not from another site" {
  let store = fleet_store()
  defer store.close()
  with_admin(store, 1_800_000_000, base => {
    store.mind("tigress")
    store.mind("flea")
    let form = "ship=tigress&ship=flea&text=A+dust+front%2C+%E2%80%9Cthick%E2%80%9D."
    let (res, _) = @http.post(
      "\{base}/admin/hails",
      form,
      headers=admin_headers([
        ("Content-Type", "application/x-www-form-urlencoded"),
        ("Origin", "https://evil.example"),
      ]),
    )
    inspect(res.code, content="403")
    let (res, _) = @http.post(
      "\{base}/admin/hails",
      form,
      headers=admin_headers([
        ("Content-Type", "application/x-www-form-urlencoded"),
        ("Origin", base),
      ]),
    )
    inspect(res.code, content="303")
    debug_inspect(res.headers.get("Location"), content="Some(\"/admin#hails\")")
    debug_inspect(
      store.hails().map(h => (h.ship, h.text)),
      content=(
        #|[
        #|  ("flea", "A dust front, “thick”."),
        #|  ("tigress", "A dust front, “thick”."),
        #|]
      ),
    )
  })
}

///|
async test "the admin page shows each hail and what came of it" {
  let store = fleet_store()
  defer store.close()
  let _ = store.hail("tigress", "<i>Dust</i> ahead.", now=1_800_000_000)
  let id = store.hail("flea", "Be cruel.", now=1_800_000_010).unwrap()
  store.silence(id, reason="blocked (cruelty): Be cruel.", now=1_800_000_020)
  with_admin(store, 1_800_000_060, base => {
    let (_, body) = @http.get(
      "\{base}/admin",
      headers=basic("YWRtaW46aHVudGVyMg=="),
    )
    let html = body.text()
    assert_true(html.contains("<form method=\"post\" action=\"/admin/hails\""))
    assert_true(html.contains("&lt;i&gt;Dust&lt;/i&gt; ahead."))
    assert_true(html.contains("waiting"))
    assert_true(html.contains("blocked (cruelty): Be cruel."))
  })
}
