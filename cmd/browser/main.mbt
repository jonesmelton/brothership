///|
/// Client state. Rendering reads `predicted()`, which already includes
/// proposals the server has not answered yet, advanced to the local clock.
struct Model {
  /// This browser's crew id. See `crew_id`.
  crew : String
  /// The local wall clock in Unix seconds, as of the last `Tock`.
  now : Int64
  /// The ships in service, once listed.
  ships : Array[@core.Listing]
  /// The ship this player is aboard, kept in `localStorage`.
  ship : String?
  /// The newest `seq` of the ship's story this browser had seen before this
  /// visit, for "while you were away"; `None` on a first visit.
  seen : Int64?
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
  Listed(Result[Array[@core.Listing], Error])
  Choose(String)
  Loaded(String, Result[@core.Snapshot, Error])
  Propose(@core.Intent)
  Settled(String, Result[@core.Receipt, Error])
  Storied(String, Result[@core.Story, Error])
  Hear(Hear)
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
  (
    {
      ..model,
      ship: Some(ship),
      seen: if seen < 0L {
        None
      } else {
        Some(seen)
      },
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
    // A line is on its way: look for it sooner than the poll would.
    (_, Tock) =>
      (
        { ..model, now: unix_now(), },
        match model.ship {
          Some(ship) if model.told.speaking =>
            tell(emit, ship, model.told.last())
          _ => @rabbita.none
        },
      )
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
        you=model.crew,
        hear=model.hear,
        ship=epithet(model),
      )
      let said = if polite == "" && assertive == "" {
        model.said
      } else {
        { polite, assertive, count: model.said.count + 1, }
      }
      let last = told.last()
      (
        { ..model, told, said, },
        @rabbita.effect(() => store_seen(ship, last.to_string())),
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
    (Ready(sync), Propose(intent)) =>
      match model.ship {
        None => (model, @rabbita.none)
        Some(ship) => {
          let standing = sync
            .predicted()
            .crossing()
            .bind(c => c.hands.get(model.crew))
            .bind(h => h.order)
          try sync.propose(model.crew, intent) catch {
            // Refused locally: the server would refuse it too.
            _ => (model, @rabbita.none)
          } noraise {
            (next, _) => {
              let focus = match focus_after(intent, standing) {
                Some(id) => focus_cmd(id)
                None => @rabbita.none
              }
              (
                { ..model, sync: Ready(next), },
                @rabbita.batch([send_next(emit, ship, sync, next), focus]),
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
  @html.section([@html.h2("Where the ship is"), ..body])
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
/// The five choices of a check-in, always in the same order: post, watch,
/// standing order, craft, and refit for engineers. Only the post is offered
/// to someone not yet aboard.
fn choices(
  emit : @rabbita.Emit[Msg],
  c : @core.Crossing,
  crew : String,
) -> Array[@rabbita.Html] {
  let hand = c.hands.get(crew)
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
      let longest = @core.max_watch(h.rank) / @core.HOUR
      let hours : Array[Int64] = [1, 2, 4, 8, 12]
      [
        group(
          "watch",
          "Watch",
          hours
          .filter(n => n <= longest)
          .map(n => {
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
  let refit = if h.craft == Engineer {
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
  } else {
    []
  }
  [post, ..watch, ..order, craft, ..refit]
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
    return page(model, [masthead("Choose a ship"), ..body])
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
      let away = model.told
        .away(model.seen, you=model.crew, ship=epithet(model))
        .map(line => @html.li(line))
      [
        where_section(s),
        @html.section([@html.h2("While you were away"), @html.ul(away)]),
        @html.section(
          [@html.h2("You"), ..sentences(@words.you_sentences(s, model.crew))],
        ),
        @html.section(
          [
            @html.h2("Choices"),
            ..match s.crossing() {
              Some(c) => choices(emit, c, model.crew)
              None => [@html.p("Choices open when the ship departs.")]
            },
          ],
        ),
        log_section(model, emit),
      ]
    }
  }
  let other = @html.section([@html.h2("Other ships"), ship_choices(model, emit)])
  page(model, [masthead(title(name)), ..body, other])
}

///|
/// How many entries the log shows, newest first.
const LOG_LENGTH : Int32 = 20

///|
/// The ship's log, newest first, and the choice of what is read aloud.
fn log_section(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  let ship = epithet(model)
  let entries = model.told.entries
  let start = (entries.length() - LOG_LENGTH).max(0)
  let items = entries[start:]
    .to_owned()
    .rev()
    .map(e => {
      let line = @words.told(e.happening, you=model.crew, ship~)
      let when = @words.ago((model.now - e.at).max(0L))
      @html.li(class=if e.happening is Spoke(_) { "voice" } else { "" }, [
        @html.text(line),
        @html.text(" "),
        @html.span(class="when", when),
      ])
    })
  let speaking = if model.told.speaking {
    [@html.p(class="pending", "\{ship} is finding words.")]
  } else {
    []
  }
  let log = if items.is_empty() {
    [@html.p("Nothing yet.")]
  } else {
    [
      // Without markers Safari drops list semantics unless asked.
      @html.ul(class="log", attrs=@html.Attrs::build().role("list"), items),
    ]
  }
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
  @html.section([@html.h2("Log"), ..speaking, ..log, hear])
}

///|
/// The page: `content` and the two live regions, which are always present
/// so that screen readers are watching them before anything is said.
fn page(model : Model, content : Array[@rabbita.Html]) -> @rabbita.Html {
  // A trailing space on alternate updates makes repeated words new text.
  let pad = if model.said.count % 2 == 1 { "\u{a0}" } else { "" }
  let region = (politeness : String, text : String) => {
    @html.div(
      class="visually-hidden",
      attrs=@html.Attrs::build().aria_live(politeness).aria_atomic("true"),
      text + pad,
    )
  }
  @html.div([
    @html.main_(class="checkin", content),
    region("polite", model.said.polite),
    region("assertive", model.said.assertive),
  ])
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
          crew: crew_id(),
          now: unix_now(),
          ships: [],
          ship: if ship == "" {
            None
          } else {
            Some(ship)
          },
          seen: None,
          told: Told::new(),
          hear: Hear::parse(stored_hear()),
          said: { polite: "", assertive: "", count: 0, },
          sync: Loading,
        }
        (model, list(emit))
      },
      update~,
      subscriptions=(_, emit) => {
        @sub.batch([
          @sub.every(TOCK_MS, emit(Tock)),
          @sub.every(POLL_MS, emit(Poll)),
        ])
      },
    )
    model.view(model => view(model, emit))
  }).mount("app")
}
