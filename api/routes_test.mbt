///|
/// Serve `store` on a free port at a fixed clock and run `f` with its base URL.
async fn with_server(
  store : @store.Store,
  now : Int64,
  f : async (String) -> Unit,
  mint_each~ : @api.Limiter = @api.Limiter::new(burst=1000, interval=1),
) -> Unit {
  let app = @moonback.App(@api.routes(store, clock=() => now, mint_each~))
  defer app.close()
  let listener = @moonback.listen(host="127.0.0.1", port=0)
  let base = "http://127.0.0.1:\{listener.addr.port()}"
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => app.serve(listener))
    f(base)
  })
}

///|
async fn fleet_store() -> @store.Store {
  let store = @store.Store::open(":memory:")
  for berth in @ships.fleet() {
    store.commission(berth)
  }
  store
}

///|
/// The session cookie a browser gets, and the officer it names.
async fn new_session(base : String) -> (@http.Cookie, @core.Session) {
  let (response, body) = @http.get("\{base}/api/session")
  let session : @core.Session = @json.from_json(body.json())
  (
    response.cookies
    .iter()
    .find_first(cookie => cookie.name == "session")
    .unwrap(),
    session,
  )
}

///|
/// The `Cookie` request header for `cookie`.
fn cookie_header(
  cookie : @http.Cookie,
) -> Map[@http.CaseInsensitiveString, String] {
  { "Cookie": "session=\{cookie.value}" }
}

///|
async test "api round trip over http" {
  let store = fleet_store()
  defer store.close()
  store.advance("tigress", now=1_800_000_000)
  store.advance("tigress", now=1_800_000_600)
  with_server(store, 1_800_000_660, base => {
    let (cookie, session) = new_session(base)
    let headers = cookie_header(cookie)
    let (_, body) = @http.get("\{base}/api/ships")
    json_inspect(body.json(), content=[
      {
        "id": "tigress",
        "name": "EF-147 The Tigress",
        "crossings": "0",
        "from": "Kerala",
        "bound": "Occitan",
        "whereabouts": ["Underway", { "arrives": "1800069192" }],
        "run": "0",
        "officers": "0",
      },
      {
        "id": "scorpion",
        "name": "HS-212 The Twin-Tailed Scorpion",
        "crossings": "0",
        "from": "Kerala",
        "whereabouts": ["InPort", { "departs": "600" }],
        "run": "0",
        "officers": "0",
      },
      {
        "id": "flea",
        "name": "EF-287 The Flea on the Drum",
        "crossings": "0",
        "from": "Kerala",
        "whereabouts": ["InPort", { "departs": "600" }],
        "run": "0",
        "officers": "0",
      },
    ])
    let (_, body) = @http.get("\{base}/api/ships/tigress/snapshot")
    let snapshot : @core.Snapshot = @json.from_json(body.json())
    inspect(snapshot == store.snapshot("tigress").unwrap(), content="true")
    let proposal : @core.Proposal = {
      id: 1,
      crew: session.officer,
      intent: Posted(post=Hull),
    }
    let (_, body) = @http.post(
      "\{base}/api/ships/tigress/proposals",
      proposal.to_json(),
      headers~,
    )
    let receipt : @core.Receipt = @json.from_json(body.json())
    inspect(receipt is Accepted(id=1, ..), content="true")
    inspect(receipt.snapshot().state.at, content="1800000660")
    debug_inspect(session.ship, content="None")
    let (_, body) = @http.get("\{base}/api/session", headers~)
    let aboard : @core.Session = @json.from_json(body.json())
    debug_inspect(aboard.ship, content="Some(\"tigress\")")
    let (res, _) = @http.get("\{base}/api/ships/flea/snapshot", headers~)
    inspect(res.code, content="403")
    let (res, _) = @http.get("\{base}/api/ships/flea/story?after=0", headers~)
    inspect(res.code, content="403")
    let (res, _) = @http.get("\{base}/api/ships/tigress/snapshot", headers~)
    inspect(res.code, content="200")
    let (res, _) = @http.post(
      "\{base}/api/ships/flea/proposals",
      proposal.to_json(),
      headers~,
    )
    inspect(res.code, content="403")
    let (res, body) = @http.post(
      "\{base}/api/ships/tigress/proposals",
      "{\"id\":",
    )
    inspect(res.code, content="400")
    json_inspect(body.json(), content={ "error": "Unexpected end of file" })
    let (res, _) = @http.get("\{base}/api/ships/nobody/snapshot")
    inspect(res.code, content="404")
    let (res, _) = @http.post(
      "\{base}/api/ships/nobody/proposals",
      proposal.to_json(),
      headers~,
    )
    inspect(res.code, content="404")
  })
}

///|
async test "the session cookie names one officer and is HttpOnly" {
  let store = fleet_store()
  defer store.close()
  with_server(store, 1_800_000_000, base => {
    let (cookie, session) = new_session(base)
    inspect(cookie.http_only, content="true")
    inspect(cookie.secure, content="true")
    inspect(cookie.path.unwrap_or(""), content="/")
    inspect(cookie.max_age.unwrap_or(0L), content="2592000")
    inspect(cookie.extensions.contains("SameSite=Lax"), content="true")
    inspect(session.officer.has_prefix("OF-"), content="true")
    inspect(session.officer.length(), content="10")
    let (response, body) = @http.get(
      "\{base}/api/session",
      headers=cookie_header(cookie),
    )
    let again : @core.Session = @json.from_json(body.json())
    inspect(again == session, content="true")
    inspect(response.cookies.is_empty(), content="true")
  })
}

///|
async test "a proposal acts only as its session's officer" {
  let store = fleet_store()
  defer store.close()
  store.advance("tigress", now=1_800_000_000)
  store.advance("tigress", now=1_800_000_600)
  with_server(store, 1_800_000_660, base => {
    let (cookie, session) = new_session(base)
    let headers = cookie_header(cookie)
    let wrong : @core.Proposal = {
      id: 1,
      crew: "officer-other",
      intent: Posted(post=Drive),
    }
    let (res, _) = @http.post(
      "\{base}/api/ships/tigress/proposals",
      wrong.to_json(),
      headers~,
    )
    inspect(res.code, content="403")
    let (res, _) = @http.post(
      "\{base}/api/ships/tigress/proposals",
      wrong.to_json(),
    )
    inspect(res.code, content="401")
    let right : @core.Proposal = { ..wrong, crew: session.officer, }
    let (res, body) = @http.post(
      "\{base}/api/ships/tigress/proposals",
      right.to_json(),
      headers~,
    )
    inspect(res.code, content="200")
    let receipt : @core.Receipt = @json.from_json(body.json())
    inspect(receipt is Accepted(id=1, ..), content="true")
    inspect(
      receipt.snapshot().state.crossing().unwrap().count(Drive),
      content="1",
    )
  })
}

///|
/// The path `fly.toml` checks. It must not depend on the game API's shape.
async test "health check answers 200" {
  let store = fleet_store()
  defer store.close()
  with_server(store, 1_800_000_000, base => {
    let (res, body) = @http.get("\{base}/healthz")
    inspect(res.code, content="200")
    json_inspect(body.json(), content={ "ok": true })
  })
}

///|
async test "a proposal naming a server event is refused with 400" {
  let store = fleet_store()
  defer store.close()
  with_server(store, 1_800_000_000, base => {
    let tick : Json = {
      "id": "1",
      "crew": "ann",
      "intent": ["Tick", { "at": "9999999999" }],
    }
    let (res, _) = @http.post("\{base}/api/ships/tigress/proposals", tick)
    inspect(res.code, content="400")
    inspect(store.snapshot("tigress").unwrap().seq, content="1")
  })
}

///|
async test "the story route returns entries after a seq" {
  let store = fleet_store()
  defer store.close()
  store.advance("tigress", now=1_800_000_000)
  store.advance("tigress", now=1_800_000_600)
  with_server(store, 1_800_000_660, base => {
    let (_, body) = @http.get("\{base}/api/ships/tigress/story?after=0")
    let story : @core.Story = @json.from_json(body.json())
    inspect(
      story.entries == store.story("tigress", after=0).unwrap(),
      content="true",
    )
    inspect(story.speaking, content="false")
    let last = story.entries.last().unwrap().seq
    let (_, body) = @http.get("\{base}/api/ships/tigress/story?after=\{last}")
    let story : @core.Story = @json.from_json(body.json())
    inspect(story.entries.length(), content="0")
    let (response, _) = @http.get("\{base}/api/ships/nobody/story")
    inspect(response.code, content="404")
  })
}

///|
async test "minting sessions is limited per client, not for existing sessions" {
  let store = fleet_store()
  defer store.close()
  let mint_each = @api.Limiter::new(burst=2, interval=30)
  with_server(
    store,
    1_800_000_000,
    base => {
      let (cookie, _) = new_session(base)
      new_session(base) |> ignore
      let (res, body) = @http.get("\{base}/api/session")
      inspect(res.code, content="429")
      inspect(res.headers.get("Retry-After") is Some("30"), content="true")
      inspect(res.cookies.is_empty(), content="true")
      json_inspect(body.json(), content={ "error": "too many new sessions" })
      let (res, _) = @http.get(
        "\{base}/api/session",
        headers=cookie_header(cookie),
      )
      inspect(res.code, content="200")
      let (res, _) = @http.get("\{base}/api/session", headers={
        "Fly-Client-IP": "203.0.113.9",
      })
      inspect(res.code, content="200")
    },
    mint_each~,
  )
}

///|
async test "minting sessions is limited across all clients" {
  let store = fleet_store()
  defer store.close()
  let app = @moonback.App(
    @api.routes(
      store,
      clock=() => 1_800_000_000,
      mint_all=@api.Limiter::new(burst=1, interval=60),
    ),
  )
  defer app.close()
  let listener = @moonback.listen(host="127.0.0.1", port=0)
  let base = "http://127.0.0.1:\{listener.addr.port()}"
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => app.serve(listener))
    new_session(base) |> ignore
    let (res, _) = @http.get("\{base}/api/session", headers={
      "Fly-Client-IP": "203.0.113.9",
    })
    inspect(res.code, content="429")
  })
}
