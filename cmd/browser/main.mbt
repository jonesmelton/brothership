///|
/// Client state. Rendering reads `predicted()`, which already includes
/// proposals the server has not answered yet, advanced to the local clock.
struct Model {
  /// The officer this client acts as, from `GET /api/session` and the
  /// server-issued session cookie. Empty until the session arrives.
  officer : String
  /// The local wall clock in Unix seconds, as of the last `Tock`.
  now : Int64
  /// The ships in service, once listed.
  ships : Array[@core.Listing]
  /// The ship this player is aboard, kept in `localStorage`.
  ship : String?
  /// The newest `seq` of the ship's story this browser had seen before this
  /// visit, for "while you were away"; `None` on a first visit.
  seen : Int64?
  /// The page shown, from the address.
  page : @words.Page
  /// The newest story `seq` viewed on each page, kept in `localStorage`.
  viewed : Viewed
  /// The player's totals when this visit began, for "since you were here";
  /// `None` on a first visit. The current totals are stored as they move.
  ledger : @words.Ledger?
  /// Hours of the last watch chosen, or 0; kept in `localStorage`.
  last_watch : Int64
  /// What the last choice changed. Dropped on leaving the You page.
  effect : Array[String]
  told : Told
  hear : Hear
  said : Said
  sync : Sync
} derive(Eq)

///|
enum Sync {
  Loading
  Ready(@core.Optimistic)
  Offline(reason~ : String)
} derive(Eq)

///|
/// Replies carry the ship they are about, so one that arrives after the
/// player changed ship is dropped.
enum Msg {
  Session(Result[@core.Session, Error])
  Listed(Result[Array[@core.Listing], Error])
  Choose(String)
  Loaded(String, Result[@core.Snapshot, Error])
  Propose(@core.Intent)
  Settled(String, Result[@core.Receipt, Error])
  Storied(String, Result[@core.Story, Error])
  Hear(Hear)
  /// The address now names this page.
  Went(@words.Page)
  /// A link was followed. Rabbita stops the browser following it.
  Requested(@url.UrlRequest)
  /// The local clock moved.
  Tock
  Poll
}

///|
/// How often the screen moves its clock, and polls for what the ship did.
const TOCK_MS : Int32 = 5_000

///|
const POLL_MS : Int32 = 15_000

///|
/// The officer this browser acts as. The server sets the session cookie on
/// the first call.
fn session(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  @http.get("/api/session").expect_json(emit.map(r => Session(r)))
}

///|
fn list(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  @http.get("/api/ships").expect_json(emit.map(r => Listed(r)))
}

///|
fn load(emit : @rabbita.Emit[Msg], ship : String) -> @rabbita.Cmd {
  @http.get("/api/ships/\{ship}/snapshot").expect_json(
    emit.map(r => Loaded(ship, r)),
  )
}

///|
/// The ship's story after `after`.
fn tell(
  emit : @rabbita.Emit[Msg],
  ship : String,
  after : Int64,
) -> @rabbita.Cmd {
  @http.get("/api/ships/\{ship}/story?after=\{after}").expect_json(
    emit.map(r => Storied(ship, r)),
  )
}

///|
fn send(
  emit : @rabbita.Emit[Msg],
  ship : String,
  proposal : @core.Proposal,
) -> @rabbita.Cmd {
  @http.post("/api/ships/\{ship}/proposals")
  .with_json(proposal)
  .expect_json(emit.map(r => Settled(ship, r)))
}

///|
/// Send the in-flight proposal if settling or proposing just exposed a new one.
fn send_next(
  emit : @rabbita.Emit[Msg],
  ship : String,
  before : @core.Optimistic,
  after : @core.Optimistic,
) -> @rabbita.Cmd {
  match (before.in_flight(), after.in_flight()) {
    (Some(b), Some(a)) if a.id == b.id => @rabbita.none
    (_, Some(next)) => send(emit, ship, next)
    (_, None) => @rabbita.none
  }
}

///|
/// Board `ship`: forget the last ship's proposals and load this one.
fn board(
  model : Model,
  ship : String,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let seen = @string.parse_int64(load_seen(ship)) catch { _ => -1L }
  let viewed = Viewed::parse(load_viewed(ship)).unwrap_or({
    you: seen,
    voyage: seen,
    ship: seen,
  })
  (
    {
      ..model,
      ship: Some(ship),
      seen: if seen < 0L {
        None
      } else {
        Some(seen)
      },
      viewed,
      ledger: parse_ledger(load_ledger(ship)),
      effect: [],
      told: Told::new(),
      sync: Loading,
    },
    @rabbita.batch([
      load(emit, ship),
      tell(emit, ship, 0),
      @rabbita.effect(() => store_ship(ship)),
    ]),
  )
}

///|
/// The ship's name in English: its epithet, or the profile's name.
fn epithet(model : Model) -> String {
  let name = model.ships
    .iter()
    .find_first(l => model.ship == Some(l.id))
    .map(l => l.name)
    .unwrap_or("The ship")
  @ships.profile_named(name)
  .bind(p => p.title)
  .map(t => t.epithet)
  .unwrap_or(name)
}

///|
/// The id of the choice group that takes focus when `intent` removes the
/// control the player pressed, or `None` when that control stays. `standing`
/// is the order the cancel button would remove, which names its phase's
/// group.
fn focus_after(intent : @core.Intent, standing : @core.Order?) -> String? {
  match intent {
    Watched(_) => Some("watch")
    Ordered(order=None) =>
      standing.map(o => "order-\{@words.phase_name(o.phase)}")
    Left => Some("post")
    _ => None
  }
}

///|
/// Focus after the DOM patch, when the target exists.
fn focus_cmd(id : String) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => focus_id(id), kind=@cmd.AfterRender)
}

///|
/// The document title: the ship in English when aboard, the game otherwise.
fn page_title(model : Model) -> String {
  match model.ship {
    Some(ship) =>
      model.ships
      .iter()
      .find_first(l => l.id == ship)
      .map(l => l.name)
      .unwrap_or("brothership")
    None => "brothership"
  }
}

///|
/// Keep what the player has viewed on each page of this ship.
fn keep_viewed(model : Model) -> @rabbita.Cmd {
  match model.ship {
    Some(ship) => @rabbita.effect(() => store_viewed(ship, model.viewed.name()))
    None => @rabbita.none
  }
}

///|
/// Keep the player's current totals for the next visit's "since you were
/// here". `model.ledger` stays the one this visit began with.
fn keep_ledger(model : Model) -> @rabbita.Cmd {
  match (model.ship, model.sync) {
    (Some(ship), Ready(sync)) if model.officer != "" => {
      let ledger = @words.Ledger::of(shown(model, sync), you=model.officer)
      @rabbita.effect(() => store_ledger(ship, ledger.to_json().stringify()))
    }
    _ => @rabbita.none
  }
}

///|
fn title_cmd(model : Model) -> @rabbita.Cmd {
  @rabbita.effect(() => set_document_title(page_title(model)))
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let ready = (_ship : String, sync : @core.Optimistic, cmd : @rabbita.Cmd) => {
    ({ ..model, sync: Ready(sync), }, cmd)
  }
  let current = (ship : String) => model.ship == Some(ship)
  match (model.sync, msg) {
    (_, Session(Ok(s))) => ({ ..model, officer: s.officer, }, list(emit))
    (_, Session(Err(err))) =>
      ({ ..model, sync: Offline(reason=err.to_string()), }, @rabbita.none)
    // A line is on its way: look for it sooner than the poll would.
    (_, Tock) => {
      let ticked = { ..model, now: unix_now(), }
      let ask = match model.ship {
        Some(ship) if model.told.speaking || model.told.thinking =>
          tell(emit, ship, model.told.last())
        _ => @rabbita.none
      }
      (ticked, @rabbita.batch([ask, keep_ledger(ticked)]))
    }
    // Pushing the address brings the page back as `Went`.
    (_, Requested(Internal(url))) =>
      (model, @nav.push_url("#" + url.fragment.unwrap_or("")))
    (_, Requested(External(href))) => (model, @nav.load(href))
    (_, Went(page)) => {
      let moved = model.goto(page)
      let cmds = if moved.page != model.page {
        [focus_cmd("page"), keep_viewed(moved)]
      } else {
        []
      }
      (moved, @rabbita.batch(cmds))
    }
    (_, Poll) =>
      match model.ship {
        Some(ship) =>
          (
            model,
            @rabbita.batch([
              load(emit, ship),
              tell(emit, ship, model.told.last()),
            ]),
          )
        None => (model, list(emit))
      }
    (_, Hear(hear)) =>
      ({ ..model, hear, }, @rabbita.effect(() => store_hear(hear.name())))
    (_, Storied(ship, _)) if !current(ship) => (model, @rabbita.none)
    (_, Storied(_, Err(_))) => (model, @rabbita.none)
    (_, Storied(ship, Ok(story))) => {
      let (told, polite, assertive) = model.told.merge(
        story,
        you=model.officer,
        hear=model.hear,
        ship=epithet(model),
      )
      let said = if polite == "" && assertive == "" {
        model.said
      } else {
        { polite, assertive, count: model.said.count + 1, }
      }
      let last = told.last()
      let viewed = model.viewed.settle(last).mark(model.page, last)
      let next = { ..model, told, said, viewed, }
      (
        next,
        @rabbita.batch([
          @rabbita.effect(() => store_seen(ship, last.to_string())),
          keep_viewed(next),
        ]),
      )
    }
    (_, Listed(Ok(ships))) => {
      let listed = { ..model, ships, }
      let (model, cmd) = match listed.ship {
        Some(ship) if ships.iter().any(l => l.id == ship) =>
          if listed.sync is Loading {
            board(listed, ship, emit)
          } else {
            (listed, @rabbita.none)
          }
        _ => ({ ..listed, ship: None, }, @rabbita.none)
      }
      (model, @rabbita.batch([cmd, title_cmd(model)]))
    }
    (_, Listed(Err(err))) =>
      ({ ..model, sync: Offline(reason=err.to_string()), }, @rabbita.none)
    (_, Choose(ship)) => {
      let (model, cmd) = board(model, ship, emit)
      (model, @rabbita.batch([cmd, title_cmd(model), focus_cmd("title")]))
    }
    (_, Loaded(ship, _) | Settled(ship, _)) if !current(ship) =>
      (model, @rabbita.none)
    (Ready(sync), Loaded(ship, Ok(snapshot))) =>
      ready(ship, sync.resync(snapshot), @rabbita.none)
    (_, Loaded(ship, Ok(snapshot))) =>
      ready(ship, @core.Optimistic::new(snapshot), @rabbita.none)
    (Ready(_), Loaded(_, Err(_))) => (model, @rabbita.none)
    (_, Loaded(_, Err(err))) =>
      ({ ..model, sync: Offline(reason=err.to_string()), }, @rabbita.none)
    (Ready(_), Propose(_)) if model.officer == "" => (model, @rabbita.none)
    (Ready(sync), Propose(intent)) =>
      match model.ship {
        None => (model, @rabbita.none)
        Some(ship) => {
          let standing = sync
            .predicted()
            .crossing()
            .bind(c => c.hands.get(model.officer))
            .bind(h => h.order)
          try sync.propose(model.officer, intent) catch {
            // Refused locally: the server would refuse it too.
            _ => (model, @rabbita.none)
          } noraise {
            (next, _) => {
              let focus = match focus_after(intent, standing) {
                Some(id) => focus_cmd(id)
                None => @rabbita.none
              }
              let effect = @words.effect(
                shown(model, sync),
                shown(model, next),
                you=model.officer,
              )
              let hours = match intent {
                Watched(ticks~) => ticks / @core.HOUR
                _ => model.last_watch
              }
              (
                { ..model, sync: Ready(next), last_watch: hours, }.with_effect(
                  effect,
                ),
                @rabbita.batch([
                  send_next(emit, ship, sync, next),
                  focus,
                  if hours != model.last_watch {
                    @rabbita.effect(() => store_watch(hours.to_string()))
                  } else {
                    @rabbita.none
                  },
                ]),
              )
            }
          }
        }
      }
    (Ready(sync), Settled(ship, Ok(receipt))) => {
      let next = sync.settle(receipt)
      ready(
        ship,
        next,
        @rabbita.batch([
          send_next(emit, ship, sync, next),
          tell(emit, ship, model.told.last()),
        ]),
      )
    }
    // The in-flight proposal's fate is unknown; drop local guesses and settle
    // to whatever the server has.
    (Ready(sync), Settled(ship, Err(_))) =>
      (
        { ..model, sync: Ready(@core.Optimistic::new(sync.confirmed())), },
        load(emit, ship),
      )
    (_, Propose(_) | Settled(_)) => (model, @rabbita.none)
  }
}

///|
/// The predicted state, advanced locally to the wall clock. The client
/// never proposes a tick; this one exists only on screen.
fn shown(model : Model, sync : @core.Optimistic) -> @core.State {
  let s = sync.predicted()
  s.apply(Tick(at=model.now)) catch {
    _ => s
  }
}

///|
fn sentences(lines : Array[String]) -> Array[@rabbita.Html] {
  lines.map(line => @html.p(line))
}

///|
/// A ship's title as pennant, conventional name and epithet. The
/// conventional name is hidden from assistive technology, so the accessible
/// name is the English title. See docs/translation.md.
fn title(name : String) -> Array[@rabbita.Html] {
  match @ships.profile_named(name).bind(p => p.title) {
    Some(t) =>
      [
        @html.span(class="pennant", t.pennant),
        @html.text(" "),
        @html.span(
          class="han",
          attrs=@html.Attrs::build().lang("zh-Hant").aria_hidden("true"),
          t.conventional_name,
        ),
        @html.text(" "),
        @html.span(class="epithet", t.epithet),
      ]
    None => [@html.span(class="epithet", name)]
  }
}

///|
/// Where the ship is, with the voyage track after the phase sentence and
/// the ship's ask in its own voice.
fn where_section(s : @core.State) -> @rabbita.Html {
  let lines = @words.where_sentences(s)
  let ask = match s.crossing() {
    Some(c) => @words.ask_sentence(c)
    None => []
  }
  let body = []
  for i, line in lines {
    if ask.contains(line) {
      body.push(@html.p(class="voice", line))
    } else {
      body.push(@html.p(line))
    }
    if i == 0 && s.crossing() is Some(c) && c.phase != Arrived {
      body.push(track(c))
    }
  }
  @html.section([@html.h3("Where the ship is"), ..body])
}

///|
/// A choice. `pressed` marks the one in force, as a toggle button.
fn choice(
  emit : @rabbita.Emit[Msg],
  label : String,
  intent : @core.Intent,
  pressed? : Bool,
) -> @rabbita.Html {
  let attrs = match pressed {
    Some(p) => @html.Attrs::build().aria_pressed(p.to_string())
    None => @html.Attrs::build()
  }
  @html.button(type_="button", on_click=emit(Propose(intent)), attrs~, label)
}

///|
/// A choice group, focusable so it can take focus after its last control
/// goes away. Nothing tab-stops to it; see docs/accessibility.md.
fn group(
  id : String,
  legend : String,
  buttons : Array[@rabbita.Html],
) -> @rabbita.Html {
  @html.fieldset(
    id~,
    attrs=@html.Attrs::build().tabindex(-1),
    [@html.legend(legend), ..buttons],
  )
}

///|
/// The choices of the You page, always in the same order: post, watch,
/// standing order and craft. Only the post is offered to someone not yet
/// aboard. `reup` is a watch just stood, offered again first.
fn choices(
  emit : @rabbita.Emit[Msg],
  c : @core.Crossing,
  officer : String,
  reup : Int64?,
) -> Array[@rabbita.Html] {
  let hand = c.hands.get(officer)
  let at = hand.map(h => h.post)
  let posts : Array[@core.Post] = [Drive, Hull, Craft]
  let post = group(
    "post",
    "Post",
    posts.map(p => {
      choice(emit, @words.post_label(p), Posted(post=p), pressed=at == Some(p))
    }) +
    (if hand is Some(_) { [choice(emit, "Leave the crew", Left)] } else { [] }),
  )
  guard hand is Some(h) else { [post] }
  let watch = match h.watch {
    Some(_) =>
      [group("watch", "Watch", [@html.p("On watch. Changing post breaks it.")])]
    None => {
      let again = match reup {
        Some(n) => [choice(emit, reup_label(n), Watched(ticks=n * @core.HOUR))]
        None => []
      }
      [
        group(
          "watch",
          "Watch",
          again +
          watch_hours.map(n => {
            choice(
              emit,
              @words.plural(n, "hour", "hours"),
              Watched(ticks=n * @core.HOUR),
            )
          }),
        ),
      ]
    }
  }
  let phases : Array[@core.Phase] = [Coast, Approach]
  let later = phases.filter(p => {
    p > c.phase && (p != Coast || c.plan.coast > 0L)
  })
  // One group per phase, so no group holds more than four buttons.
  let order = later.map(phase => {
    let buttons = posts.map(p => {
      let order : @core.Order = { phase, post: p, }
      choice(
        emit,
        @words.post_label(p),
        Ordered(order=Some(order)),
        pressed=h.order == Some(order),
      )
    })
    let cancel = match h.order {
      Some(o) if o.phase == phase =>
        [choice(emit, "Cancel the order", Ordered(order=None))]
      _ => []
    }
    group(
      "order-\{@words.phase_name(phase)}",
      "When the \{@words.phase_name(phase)} begins",
      buttons + cancel,
    )
  })
  let crafts : Array[@core.Craft] = [Artist, Engineer]
  let craft = group(
    "craft",
    "Craft",
    crafts.map(k => {
      choice(
        emit,
        @words.craft_label(k),
        Crafted(craft=k),
        pressed=h.craft == k,
      )
    }),
  )
  [post, ..watch, ..order, craft]
}

///|
/// The refit choice, for engineers; the Ship page offers it.
fn refit_choices(
  emit : @rabbita.Emit[Msg],
  c : @core.Crossing,
  officer : String,
) -> Array[@rabbita.Html] {
  guard c.hands.get(officer) is Some(h) && h.craft == Engineer else { [] }
  [
    group(
      "refit",
      "Refit",
      @core.refits
      .filter(r => c.fit.can_refit(r))
      .map(r => {
        choice(
          emit,
          @words.refit_label(r),
          Refitting(refit=Some(r)),
          pressed=c.fit.refit == Some(r),
        )
      }),
    ),
  ]
}

///|
/// How many hours of watch to offer again to `officer`, if any.
fn Model::reup_hours(self : Model, c : @core.Crossing) -> Int64? {
  guard c.hands.get(self.officer) is Some({ watch: None, .. }) else { None }
  reup(self.told.entries, self.officer, self.last_watch)
}

///|
/// The ships to board, in a fixed order, the current one pressed.
fn ship_choices(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  // A div, not a fieldset: the heading above already names the list.
  @html.div(
    class="choice-row",
    model.ships.map(l => {
      @html.button(
        type_="button",
        on_click=emit(Choose(l.id)),
        attrs=@html.Attrs::build().aria_pressed(
          (model.ship == Some(l.id)).to_string(),
        ),
        title(l.name),
      )
    }),
  )
}

///|
fn view(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  guard model.ship is Some(ship) else {
    let body = match model.sync {
      Offline(reason~) => [@html.p("Out of contact with the fleet: \{reason}")]
      _ if model.ships.is_empty() => [@html.p("Reaching the fleet.")]
      _ => [ship_choices(model, emit)]
    }
    return page(model, [masthead("Choose a ship"), ..body], [])
  }
  let name = model.ships
    .iter()
    .find_first(l => l.id == ship)
    .map(l => l.name)
    .unwrap_or(ship)
  let body = match model.sync {
    Loading => [@html.p("Reaching the ship.")]
    Offline(reason~) => [@html.p("Out of contact with the ship: \{reason}")]
    Ready(sync) => {
      let s = shown(model, sync)
      let sections = match model.page {
        You => you_page(model, emit, s)
        Voyage => voyage_page(model, emit, s)
        Ship => ship_page(model, emit, s)
      }
      [
        @html.h2(
          class="page",
          id="page",
          attrs=@html.Attrs::build().tabindex(-1),
          model.page.name(),
        ),
        ..sections,
      ]
    }
  }
  let nav = match model.sync {
    Ready(_) => [pages_nav(model)]
    _ => []
  }
  page(model, [masthead(title(name)), ..body], nav)
}

///|
/// The You page: what changed since the last visit, what the player earns,
/// the choices that are theirs and what the last one did, and their log.
fn you_page(
  model : Model,
  emit : @rabbita.Emit[Msg],
  s : @core.State,
) -> Array[@rabbita.Html] {
  let you = model.officer
  let since = match model.ledger {
    Some(before) => @words.since(before, @words.Ledger::of(s, you~))
    None => []
  }
  let bars = match s.crossing() {
    Some(c) =>
      [
        ..match work_span(c, you) {
          Some((done, of)) => [measure("Work toward the next work", done, of)]
          None => []
        },
        ..match service_span(c, you) {
          Some((done, of)) =>
            [measure("Service before the ship can promote you", done, of)]
          None => []
        },
      ]
    None => []
  }
  let effect = if model.effect.is_empty() {
    []
  } else {
    [@html.p(class="effect", model.effect.join(" "))]
  }
  [
    rank_line(s.rank(you)),
    away_section(model, You, "Since you were here", since),
    @html.section(
      [
        @html.h3("Your post"),
        ..sentences(@words.you_sentences(s, you)),
        ..sentences(@words.earning_sentences(s, you~)),
        ..bars,
      ],
    ),
    @html.section(
      [
        @html.h3("Choices"),
        ..match s.crossing() {
          Some(c) => choices(emit, c, you, model.reup_hours(c))
          None => [@html.p("Choices open when the ship departs.")]
        },
        ..effect,
      ],
    ),
    log_section(model, You),
  ]
}

///|
/// The Voyage page: where the ship is, how its demands will close, a way to
/// answer each open one, and the voyage's log.
fn voyage_page(
  model : Model,
  emit : @rabbita.Emit[Msg],
  s : @core.State,
) -> Array[@rabbita.Html] {
  let outlook = match s.crossing() {
    Some(c) =>
      [
        ..sentences(@words.outlook_sentences(c)),
        ..demand_choices(emit, c, model.officer),
      ]
    None => [@html.p("The ship is in port. Demands open once it departs.")]
  }
  [
    where_section(s),
    @html.section([@html.h3("Demands"), ..outlook]),
    away_section(model, Voyage, "While you were away", []),
    log_section(model, Voyage),
  ]
}

///|
/// The Ship page: the hull and fit, the refit choice, the ship's log, what is
/// read aloud, and the other ships.
fn ship_page(
  model : Model,
  emit : @rabbita.Emit[Msg],
  s : @core.State,
) -> Array[@rabbita.Html] {
  let refit = match s.crossing() {
    Some(c) =>
      [
        ..match refit_span(c) {
          Some((r, done, of)) =>
            [measure("Refit: \{@words.refit_label(r)}", done, of)]
          None => []
        },
        ..refit_choices(emit, c, model.officer),
      ]
    None => []
  }
  [
    @html.section(
      [@html.h3("The ship"), ..sentences(@words.ship_sentences(s)), ..refit],
    ),
    away_section(model, Ship, "While you were away", []),
    log_section(model, Ship),
    hear_section(model, emit),
    @html.section([@html.h3("Other ships"), ship_choices(model, emit)]),
  ]
}

///|
/// What happened on `page` while the player was away, with `extra` lines
/// first. "Nothing new" is dropped when `extra` says something.
fn away_section(
  model : Model,
  page : @words.Page,
  heading : String,
  extra : Array[String],
) -> @rabbita.Html {
  let entries = model.told.entries
  let lines = model.told.away(
    model.seen,
    you=model.officer,
    ship=epithet(model),
    on=e => @words.page_of(e, you=model.officer, story=entries) == page,
  )
  let lines = if extra.is_empty() || lines != [NOTHING_NEW] {
    extra + lines
  } else {
    extra
  }
  @html.section([@html.h3(heading), @html.ul(lines.map(l => @html.li(l)))])
}

///|
/// A button to take the post of each open demand, with how far along it is.
/// Not offered to someone already on that post.
fn demand_choices(
  emit : @rabbita.Emit[Msg],
  c : @core.Crossing,
  officer : String,
) -> Array[@rabbita.Html] {
  let at = c.hands.get(officer).map(h => h.post)
  let out = []
  for i, d in c.demands {
    guard d.status == Open else { continue }
    let post = d.hazard.post()
    let take = if at == Some(post) {
      []
    } else {
      [choice(emit, take_label(post), Posted(post~))]
    }
    out.push(
      group(
        "demand-\{i}",
        @words.hazard_name(d.hazard),
        [measure("Done", d.done, d.need), ..take],
      ),
    )
  }
  out
}

///|
fn take_label(post : @core.Post) -> String {
  "Take " + @words.post_name(post)
}

///|
/// How many entries the log shows, newest first.
const LOG_LENGTH : Int32 = 20

///|
/// One page's log, newest first. Entries newer than this visit's `seen` are
/// marked; the away list says the same in words.
fn log_section(model : Model, page : @words.Page) -> @rabbita.Html {
  let ship = epithet(model)
  let entries = model.told.entries
  let mine = entries.filter(e => {
    @words.page_of(e, you=model.officer, story=entries) == page
  })
  let start = (mine.length() - LOG_LENGTH).max(0)
  let items = mine[start:]
    .to_owned()
    .rev()
    .map(e => {
      let line = @words.told(e.happening, you=model.officer, ship~)
      let when = @words.ago((model.now - e.at).max(0L))
      let fresh = model.seen is Some(seen) && e.seq > seen
      let voice = if e.happening is Spoke(_) { "voice" } else { "" }
      @html.li(
        class=match (voice, fresh) {
          ("", false) => ""
          ("", true) => "new"
          (v, false) => v
          (v, true) => "\{v} new"
        },
        [@html.text(line), @html.text(" "), @html.span(class="when", when)],
      )
    })
  let speaking = match (page, model.told) {
    (Ship, { speaking: true, .. }) =>
      [@html.p(class="pending", "\{ship} is finding words.")]
    (Ship, { thinking: true, .. }) =>
      [@html.p(class="pending", "\{ship} is weighing a choice.")]
    _ => []
  }
  let log = if items.is_empty() {
    [@html.p("Nothing yet.")]
  } else {
    [
      // Without markers Safari drops list semantics unless asked.
      @html.ul(class="log", attrs=@html.Attrs::build().role("list"), items),
    ]
  }
  @html.section([@html.h3("Log"), ..speaking, ..log])
}

///|
/// The choice of what is read aloud as it happens.
fn hear_section(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  let hears : Array[(Hear, String)] = [
    (Everything, "Everything"),
    (Urgent, "Urgent only"),
    (Nothing, "Nothing"),
  ]
  let hear = group(
    "hear",
    "Read aloud as it happens",
    hears.map(h => {
      @html.button(
        type_="button",
        on_click=emit(Hear(h.0)),
        attrs=@html.Attrs::build().aria_pressed((model.hear == h.0).to_string()),
        h.1,
      )
    }),
  )
  @html.section([@html.h3("Read aloud"), hear])
}

///|
/// The page: `content`, the bar of links between pages if any, and the two
/// live regions, which are always present so that screen readers are
/// watching them before anything is said.
fn page(
  model : Model,
  content : Array[@rabbita.Html],
  nav : Array[@rabbita.Html],
) -> @rabbita.Html {
  // A trailing space on alternate updates makes repeated words new text.
  let pad = if model.said.count % 2 == 1 { "\u{a0}" } else { "" }
  let region = (politeness : String, text : String) => {
    @html.div(
      class="visually-hidden",
      attrs=@html.Attrs::build().aria_live(politeness).aria_atomic("true"),
      text + pad,
    )
  }
  @html.div(
    [
      @html.main_(class="checkin", content),
      ..nav,
      region("polite", model.said.polite),
      region("assertive", model.said.assertive),
    ],
  )
}

///|
fn[C : @html.IsChildren] masthead(heading : C) -> @rabbita.Html {
  @html.header(
    class="masthead",
    @html.h1(id="title", attrs=@html.Attrs::build().tabindex(-1), heading),
  )
}

///|
fn main {
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state_with_init(
      init=emit => {
        let ship = stored_ship()
        let model = {
          officer: "",
          now: unix_now(),
          ships: [],
          ship: if ship == "" {
            None
          } else {
            Some(ship)
          },
          seen: None,
          page: page_from_hash(current_hash()),
          viewed: { you: -1L, voyage: -1L, ship: -1L, },
          ledger: None,
          last_watch: @string.parse_int64(stored_watch()) catch {
            _ => 0L
          },
          effect: [],
          told: Told::new(),
          hear: Hear::parse(stored_hear()),
          said: { polite: "", assertive: "", count: 0, },
          sync: Loading,
        }
        (model, session(emit))
      },
      update~,
      subscriptions=(_, emit) => {
        @sub.batch([
          @sub.every(TOCK_MS, emit(Tock)),
          @sub.every(POLL_MS, emit(Poll)),
          @sub.on_url_request(emit.map(r => Requested(r))),
          @sub.on_url_changed(
            emit.map(u => Went(page_from_hash(u.fragment.unwrap_or("")))),
          ),
        ])
      },
    )
    model.view(model => view(model, emit))
  }).mount("app")
}
