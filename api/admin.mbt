///|
/// The realm a browser shows when it asks for the admin's credentials.
const ADMIN_REALM : String = "brothership admin"

///|
/// How many of a ship's latest happenings and lines the admin page shows.
const ADMIN_TAIL : Int32 = 40

///|
/// The longest hail accepted, in characters.
const HAIL_MAX : Int32 = 2000

///|
/// Whether `req` may use the admin pages under `admin`'s credentials. If
/// not, answers it: a 404 without credentials configured, else a 401.
async fn admitted(
  admin : (String, String)?,
  req : @moonback.Request,
  res : @moonback.Responder,
) -> Bool {
  guard admin is Some((user, password)) else {
    res.send_json({ "error": "no such page" }, status=404)
    return false
  }
  guard admin_authorized(req, user, password) else {
    res.send_text("credentials required", status=401, headers=[
      ("WWW-Authenticate", "Basic realm=\"\{ADMIN_REALM}\", charset=\"UTF-8\""),
      ("Cache-Control", "no-store"),
    ])
    return false
  }
  true
}

///|
/// Whether `req` comes from the admin page or from no page at all, such as
/// curl. A browser sends cached basic credentials with a form posted from
/// any site, so a post whose `Origin` names another host is refused.
fn same_origin(req : @moonback.Request) -> Bool {
  guard req.headers.get("Origin") is Some(origin) else { return true }
  let host = match origin.strip_prefix("https://") {
    Some(host) => Some(host)
    None => origin.strip_prefix("http://")
  }
  match (host, req.headers.get("Host")) {
    (Some(o), Some(h)) => o == h
    _ => false
  }
}

///|
/// Whether `req` carries HTTP basic credentials for `user` and `password`.
fn admin_authorized(
  req : @moonback.Request,
  user : String,
  password : String,
) -> Bool {
  guard req.headers.get("Authorization") is Some(value) &&
    value.strip_prefix("Basic ") is Some(encoded) else {
    return false
  }
  let given = @utf8.decode(@base64.decode(encoded.trim())) catch {
    _ => return false
  }
  same_text(given, "\{user}:\{password}")
}

///|
/// String equality whose time depends only on the lengths, so a wrong
/// password does not reveal how much of it was right.
fn same_text(a : String, b : String) -> Bool {
  guard a.length() == b.length() else { return false }
  let mut diff = 0
  for i in 0..<a.length() {
    diff = diff | (a.code_unit_at(i).to_int() ^ b.code_unit_at(i).to_int())
  }
  diff == 0
}

///|
/// The whole game at `now`: every ship, every officer with a session, and
/// what each ship said and thought.
async fn admin_page(
  store : @store.Store,
  now~ : Int64,
  speaking~ : (String) -> Bool,
  thinking~ : (String) -> Bool,
  thoughts~ : (String) -> Array[String],
) -> @moonback.Html {
  let ships = store.ships()
  let names : Map[String, String] = Map([])
  for id in ships {
    names[id] = @ships.listing(id, store.snapshot(id).unwrap().state).name
  }
  let officers = store.officers()
  @moonback.Html(b => {
    b <+ "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
    b <+
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
    b <+ "<title>Admin: all ships are brothers</title>"
    b <+ "<style>\{@moonback.Html::raw(ADMIN_STYLE)}</style></head><body>"
    b <+ "<header><h1>All ships are brothers</h1>"
    b <+
      "<p>The game at \{now.to_string()} Unix seconds. Reload for the latest.</p>"
    b <+
      "<nav aria-label=\"Sections\"><ul><li><a href=\"#fleet\">Fleet</a></li>"
    b <+ "<li><a href=\"#officers\">Officers</a></li>"
    b <+ "<li><a href=\"#hails\">Hails</a></li>"
    for id in ships {
      b <+ "<li><a href=\"#ship-\{id}\">\{names[id]}</a></li>"
    }
    b <+ "</ul></nav></header><main>"
    b <+ "<section aria-labelledby=\"fleet\"><h2 id=\"fleet\">Fleet</h2>"
    b <+
      "<table><caption>\{@words.plural(ships.length().to_int64(), "ship", "ships")}, in order of commission</caption>"
    b <+ "<thead><tr><th scope=\"col\">Ship</th><th scope=\"col\">Where</th>"
    b <+ "<th scope=\"col\">Officers</th><th scope=\"col\">Hands</th>"
    b <+ "<th scope=\"col\">Crossings</th><th scope=\"col\">Mind</th>"
    b <+ "<th scope=\"col\">Log position</th></tr></thead><tbody>"
    for id in ships {
      let snapshot = store.snapshot(id).unwrap()
      let s = snapshot.state
      let listing = @ships.listing(id, s)
      let hands = match s.crossing() {
        Some(c) => c.hands.length().to_string()
        None => "in port"
      }
      let mind = if !store.minded(id) {
        "scripted"
      } else if thinking(id) {
        "thinking"
      } else if speaking(id) {
        "writing a line"
      } else {
        "idle"
      }
      b <+
        "<tr><th scope=\"row\"><a href=\"#ship-\{id}\">\{listing.name}</a></th>"
      b <+ "<td>\{@words.whereabouts_sentence(listing, now~)}</td>"
      b <+ "<td>\{s.officers.length().to_string()}</td><td>\{hands}</td>"
      b <+ "<td>\{s.ship.crossings.to_string()}</td><td>\{mind}</td>"
      b <+ "<td>\{snapshot.seq.to_string()}</td></tr>"
    }
    b <+ "</tbody></table></section>"
    b <+
      "<section aria-labelledby=\"officers\"><h2 id=\"officers\">Officers</h2>"
    b <+
      "<table><caption>\{@words.plural(officers.length().to_int64(), "officer", "officers")} with a session, newest first</caption>"
    b <+
      "<thead><tr><th scope=\"col\">Service number</th><th scope=\"col\">Joined</th>"
    b <+ "<th scope=\"col\">Aboard</th><th scope=\"col\">Rank</th>"
    b <+
      "<th scope=\"col\">Post</th><th scope=\"col\">Status</th></tr></thead><tbody>"
    for pair in officers {
      let (officer, created_at) = pair
      b <+ "<tr><th scope=\"row\">\{officer}</th>"
      b <+ "<td>\{@words.ago(now - created_at)}</td>"
      match store.aboard(officer) {
        None => b <+ "<td>none</td><td></td><td></td><td></td>"
        Some(id) => {
          let s = store.snapshot(id).unwrap().state
          let o = s.officers[officer]
          let post = match o.post {
            Some(post) => @words.post_name(post)
            None => "none"
          }
          let status = [
            if o.active {
              "active"
            } else {
              "idle"
            },
            if o.leaving {
              "leaving at port"
            } else {
              ""
            },
          ]
          b <+ "<td><a href=\"#ship-\{id}\">\{names[id]}</a></td>"
          b <+ "<td>\{@words.rank_title(s.rank(officer))}</td><td>\{post}</td>"
          b <+ "<td>\{status.filter(w => w != "").join(", ")}</td>"
        }
      }
      b <+ "</tr>"
    }
    b <+ "</tbody></table></section>"
    b <+ "\{hails_section(store, names, now~)}"
    for id in ships {
      b <+ "\{ship_section(store, id, names[id], now~, thoughts=thoughts(id))}"
    }
    b <+ "</main></body></html>"
  })
}

///|
/// One ship's section of the admin page: where it is, who is aboard, its
/// mind's latest thoughts, its lines and its log.
fn ship_section(
  store : @store.Store,
  id : String,
  name : String,
  now~ : Int64,
  thoughts~ : Array[String],
) -> @moonback.Html {
  let s = store.snapshot(id).unwrap().state
  let story = store.story(id, after=0L).unwrap()
  let lines = story.filter(e => e.happening is Spoke(_))
  fn tail(a : Array[@core.Entry]) -> Array[@core.Entry] {
    a[(a.length() - ADMIN_TAIL).max(0):].to_owned().rev()
  }
  @moonback.Html(b => {
    b <+
      "<section aria-labelledby=\"ship-\{id}\"><h2 id=\"ship-\{id}\">\{name}</h2>"
    let readout = @words.readout(s)
    if readout != "" {
      b <+ "<p>\{readout}</p>"
    }
    for sentence in @words.where_rest(s) {
      b <+ "<p>\{sentence}</p>"
    }
    b <+ "<h3>Aboard</h3>"
    if s.officers.is_empty() {
      b <+ "<p>No officers aboard.</p>"
    } else {
      b <+ "<ul>"
      for officer, o in s.officers {
        let post = match o.post {
          Some(post) => ", \{@words.post_name(post)}"
          None => ""
        }
        b <+ "<li>\{officer}, \{@words.rank_name(s.rank(officer))}\{post}</li>"
      }
      b <+ "</ul>"
    }
    b <+ "<h3>Thoughts</h3>"
    if thoughts.is_empty() {
      b <+ "<p>None since the server started.</p>"
    } else {
      b <+ "<p>Oldest first. Players never see these.</p><ol>"
      for thought in thoughts {
        b <+ "<li>\{thought}</li>"
      }
      b <+ "</ol>"
    }
    b <+ "<h3>Lines</h3>"
    if lines.is_empty() {
      b <+ "<p>The ship has said nothing.</p>"
    } else {
      b <+ "<ol reversed>"
      for e in tail(lines) {
        if e.happening is Spoke(line~, ..) {
          b <+
            "<li>\{line} <small>\{@words.ago(now - e.at)}, at \{e.seq.to_string()}</small></li>"
        }
      }
      b <+ "</ol>"
    }
    b <+ "<h3>Log</h3>"
    if story.is_empty() {
      b <+ "<p>Nothing has happened since commissioning.</p>"
    } else {
      let latest = tail(story)
      b <+
        "<p>The latest \{@words.plural(latest.length().to_int64(), "happening", "happenings")} of \{story.length().to_string()}, newest first.</p>"
      b <+ "<ol reversed>"
      for e in latest {
        let told = @words.told_by(e.happening, you="", ship=name, who=as_is)
        b <+
          "<li>\{told} <small>\{@words.ago(now - e.at)}, at \{e.seq.to_string()}</small></li>"
      }
      b <+ "</ol>"
    }
    b <+ "</section>"
  })
}

///|
/// The admin page's hails: a form to send one, and the latest sent, with
/// what came of each.
async fn hails_section(
  store : @store.Store,
  names : Map[String, String],
  now~ : Int64,
) -> @moonback.Html {
  let hails = store.hails()
  let latest = hails[:hails.length().min(ADMIN_TAIL)]
  @moonback.Html(b => {
    b <+ "<section aria-labelledby=\"hails\"><h2 id=\"hails\">Hails</h2>"
    b <+
      "<p>A hail asks each ship named to tell its crew of something, in its own voice. The crew hear only the line, which the gate checks like any other.</p>"
    b <+ "<form method=\"post\" action=\"/admin/hails\">"
    b <+ "<fieldset><legend>Ships</legend>"
    for id, name in names {
      b <+
        "<label><input type=\"checkbox\" name=\"ship\" value=\"\{id}\"> \{name}</label> "
    }
    b <+ "</fieldset>"
    b <+ "<p><label for=\"hail-text\">What to speak of</label><br>"
    b <+
      "<textarea id=\"hail-text\" name=\"text\" rows=\"3\" cols=\"60\" maxlength=\"\{HAIL_MAX.to_string()}\" required></textarea></p>"
    b <+ "<p><button type=\"submit\">Send</button></p></form>"
    if latest.is_empty() {
      b <+ "<p>No hails sent.</p>"
    } else {
      b <+
        "<table><caption>The latest \{@words.plural(latest.length().to_int64(), "hail", "hails")} of \{hails.length().to_string()}, newest first</caption>"
      b <+ "<thead><tr><th scope=\"col\">Sent</th><th scope=\"col\">Ship</th>"
      b <+
        "<th scope=\"col\">Hail</th><th scope=\"col\">Outcome</th></tr></thead><tbody>"
      for h in latest {
        let outcome = match h.outcome {
          Open => "waiting"
          Spoke(seq~, ..) =>
            match store.story(h.ship, after=seq - 1).unwrap_or([]).get(0) {
              Some({ happening: Spoke(line~, ..), .. }) => "said: \{line}"
              _ => "said at \{seq.to_string()}"
            }
          Silent(reason~, ..) => reason
        }
        b <+ "<tr><td>\{@words.ago(now - h.sent_at)}</td>"
        b <+ "<td>\{names.get(h.ship).unwrap_or(h.ship)}</td>"
        b <+ "<td>\{h.text}</td><td>\{outcome}</td></tr>"
      }
      b <+ "</tbody></table>"
    }
    b <+ "</section>"
  })
}

///|
const ADMIN_STYLE : String =
  #|body { font: 1rem/1.5 system-ui, sans-serif; max-width: 72em; margin: 0 auto; padding: 1em; }
  #|table { border-collapse: collapse; width: 100%; }
  #|caption { text-align: left; font-weight: bold; }
  #|th, td { text-align: left; vertical-align: top; padding: 0.25em 0.5em; border-bottom: 1px solid #ccc; }
  #|nav ul { display: flex; flex-wrap: wrap; gap: 0 1em; padding: 0; list-style: none; }
  #|small { color: #555; }
  #|section { margin-top: 2em; }
  #|@media (prefers-color-scheme: dark) { body { background: #111; color: #eee; } small { color: #aaa; } a { color: #9cf; } }

///|
/// The admin page names every crew member by id.
fn as_is(crew : String) -> String {
  crew
}
