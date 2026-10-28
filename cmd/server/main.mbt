///|
async fn main {
  let host = @env.get_env_var("WARREN_HOST").unwrap_or("127.0.0.1")
  let port = @string.parse_uint(
    @env.get_env_var("WARREN_PORT").unwrap_or("4300"),
  )
  guard port > 0 && port <= 65535 else { fail("Invalid WARREN_PORT") }
  let dist = @env.get_env_var("WARREN_DIST").unwrap_or(
    @path.Path(@env.args()[0]).resolve().dirname().to_string(),
  )
  let db = @env.get_env_var("BROTHERSHIP_DB").unwrap_or("brothership.sqlite")
  let store = @store.Store::open(db)
  for berth in @ships.fleet() {
    store.commission(berth)
  }
  defer store.close()
  let speakers = speakers(store)
  let assets = warren_assets()
  let dev = @env.get_env_var("WARREN_MODE") == Some("DEV")
  let client = if dev { @env.get_env_var("WARREN_CLIENT") } else { None }
  let resources = if dev || assets.is_empty() {
    @static.new(root=dist, rewrite_trailing_slash_index=true)
  } else {
    @static.from_assets(assets, rewrite_trailing_slash_index=true)
  }
  let app = @moonback.App(ctx => {
    ctx.add_middleware(
      @moonback.Middleware(next => {
        let serve = (resources.0)(next)
        (req, res) => {
          if client is Some(_) && req.path == "/" {
            next(req, res)
          } else {
            serve(req, res)
          }
        }
      }),
    )
    if client is Some(client) {
      ctx.get("/", (_req, res) => {
        let html = @fs.read_file(
          @path.Path(dist).join("index.html").to_string(),
        ).text()
        let (head, tail) = html
          .split_once("</head>")
          .map_or((html, ""), parts => (parts.0.to_owned(), "</head>\{parts.1}"))
        res.send_html(
          @moonback.Html(b => {
            b <+ "\{@moonback.Html::raw(head)}"
            b <+ "<script src=\"\{client}\" defer></script>"
            b <+ "\{@moonback.Html::raw(tail)}"
          }),
        )
      })
    }
    ctx.use_(
      @api.routes(store, speaking=ship => {
        speakers.iter().any(sp => sp.0 == ship && sp.1.speaking())
      }),
    )
  })
  defer app.close()
  let listener = @moonback.listen(host~, port=port.to_uint16(), reuse_addr=true)
  println("Server is running on http://\{host}:\{port} (db: \{db})")
  @async.with_task_group(group => {
    for berth in @ships.fleet() {
      group.spawn_bg(() => ship_clock(store, berth))
    }
    for sp in speakers {
      group.spawn_bg(() => speak(store, sp.1))
    }
    app.serve(listener)
  })
}

///|
/// Moves one ship's game time on its own: advances it, then sleeps until
/// the berth's next advance (`Berth::next_advance`). Each berth has its own
/// second in the minute, so ships never take their turns together.
async fn ship_clock(store : @store.Store, berth : @ships.Berth) -> Unit {
  while true {
    let state = store.snapshot(berth.id).unwrap().state
    let now = @api.unix_now()
    let wait = berth.next_advance(state, now) - now
    @async.sleep((wait * 1000L).to_int())
    store.advance(berth.id, now=@api.unix_now())
  }
}

///|
/// Where the server reads speech prompts and ships' faces, relative to its
/// working directory.
const CONTENT : String = "content"

///|
/// The model that writes ships' lines, and the one that gates them.
const WRITER : String = "meta:muse-spark-1.3"

///|
const GATE : String = "meta:muse-spark-1.3"

///|
/// How often a speaker looks for something to answer, in milliseconds.
const LISTEN_MS : Int32 = 3_000

///|
/// One speaker per ship with faces, by ship id. None without a model key.
async fn speakers(store : @store.Store) -> Array[(String, @speech.Speaker)] {
  guard @speech.meta_key() is Some(key) else {
    println("speech: no MODEL_API_KEY, ships will not speak")
    return []
  }
  let speech = @speech.Speech::load(
    content=CONTENT,
    model=WRITER,
    gate_model=GATE,
  )
  let backend = @speech.meta_backend(key)
  let out = []
  for berth in @ships.fleet() {
    guard berth.profile.title is Some(title) &&
      @speech.Voice::load(content=CONTENT, title) is Some(voice) else {
      continue
    }
    // Answer only what happens from now on.
    let from = store.snapshot(berth.id).map(s => s.seq).unwrap_or(0L)
    out.push(
      (berth.id, @speech.Speaker::new(berth.id, voice, speech, backend, from~)),
    )
    println("speech: \{berth.id} speaks as \{voice.epithet}")
  }
  out
}

///|
/// Lets one ship answer what happens to it, for as long as the server runs.
async fn speak(store : @store.Store, speaker : @speech.Speaker) -> Unit {
  while true {
    speaker.step(store, clock=@api.unix_now)
    @async.sleep(LISTEN_MS)
  }
}
