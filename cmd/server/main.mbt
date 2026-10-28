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
  let store = @store.Store::open(
    db,
    ship=@ships.flagship(),
    seed=@ships.FLAGSHIP_SEED,
  )
  defer store.close()
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
    ctx.use_(@api.routes(store))
  })
  defer app.close()
  let listener = @moonback.listen(host~, port=port.to_uint16(), reuse_addr=true)
  println("Server is running on http://\{host}:\{port} (db: \{db})")
  @async.with_task_group(group => {
    group.spawn_bg(() => ship_clock(store))
    app.serve(listener)
  })
}

///|
/// Longest the ship clock sleeps, in seconds, so a changed clock or a missed
/// instant is caught within a minute.
const MAX_SLEEP : Int64 = 60L

///|
/// Moves game time on its own: sleeps until the ship next has something to
/// do, or a minute, then appends the tick and whatever the ship does then.
async fn ship_clock(store : @store.Store) -> Unit {
  while true {
    let now = @api.unix_now()
    store.advance(now~)
    let wait = (store.wake() - now).clamp(min=1L, max=MAX_SLEEP)
    @async.sleep((wait * 1000L).to_int())
  }
}
