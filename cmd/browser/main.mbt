///|
/// Client state. Rendering reads `predicted()`, which already includes
/// proposals the server has not answered yet, advanced to the local clock.
struct Model {
  /// This browser's crew id. See `crew_id`.
  crew : String
  /// The local wall clock in Unix seconds, as of the last `Tock`.
  now : Int64
  /// The state at the player's last visit, for "while you were away".
  since : @core.State?
  sync : Sync
} derive(Eq)

///|
enum Sync {
  Loading
  Ready(@core.Optimistic)
  Offline(reason~ : String)
} derive(Eq)

///|
enum Msg {
  Loaded(Result[@core.Snapshot, Error])
  Propose(@core.Intent)
  Settled(Result[@core.Receipt, Error])
  /// The local clock moved.
  Tock
}

///|
/// How often the screen moves its clock, and polls for what the ship did.
const TOCK_MS : Int32 = 5_000

///|
const POLL_MS : Int32 = 15_000

///|
fn load(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  @http.get("/api/snapshot").expect_json(emit.map(r => Loaded(r)))
}

///|
fn send(emit : @rabbita.Emit[Msg], proposal : @core.Proposal) -> @rabbita.Cmd {
  @http.post("/api/proposals")
  .with_json(proposal)
  .expect_json(emit.map(r => Settled(r)))
}

///|
/// Send the in-flight proposal if settling or proposing just exposed a new one.
fn send_next(
  emit : @rabbita.Emit[Msg],
  before : @core.Optimistic,
  after : @core.Optimistic,
) -> @rabbita.Cmd {
  match (before.in_flight(), after.in_flight()) {
    (Some(b), Some(a)) if a.id == b.id => @rabbita.none
    (_, Some(next)) => send(emit, next)
    (_, None) => @rabbita.none
  }
}

///|
/// Remember what the player has now seen, for their next visit.
fn remember(sync : @core.Optimistic) -> @rabbita.Cmd {
  let state = sync.confirmed().state
  @rabbita.effect(() => store_seen(state.to_json().stringify()))
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let ready = (sync : @core.Optimistic, cmd : @rabbita.Cmd) => {
    ({ ..model, sync: Ready(sync), }, @rabbita.batch([cmd, remember(sync)]))
  }
  match (model.sync, msg) {
    (_, Tock) => ({ ..model, now: unix_now(), }, @rabbita.none)
    (Ready(sync), Loaded(Ok(snapshot))) =>
      ready(sync.resync(snapshot), @rabbita.none)
    (_, Loaded(Ok(snapshot))) =>
      ready(@core.Optimistic::new(snapshot), @rabbita.none)
    (Ready(_), Loaded(Err(_))) => (model, @rabbita.none)
    (_, Loaded(Err(err))) =>
      ({ ..model, sync: Offline(reason=err.to_string()), }, @rabbita.none)
    (Ready(sync), Propose(intent)) =>
      try sync.propose(model.crew, intent) catch {
        // Refused locally: the server would refuse it too.
        _ => (model, @rabbita.none)
      } noraise {
        (next, _) =>
          ({ ..model, sync: Ready(next), }, send_next(emit, sync, next))
      }
    (Ready(sync), Settled(Ok(receipt))) => {
      let next = sync.settle(receipt)
      ready(next, send_next(emit, sync, next))
    }
    // The in-flight proposal's fate is unknown; drop local guesses and settle
    // to whatever the server has.
    (Ready(sync), Settled(Err(_))) =>
      (
        { ..model, sync: Ready(@core.Optimistic::new(sync.confirmed())), },
        load(emit),
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
fn group(legend : String, buttons : Array[@rabbita.Html]) -> @rabbita.Html {
  @html.fieldset([@html.legend(legend), ..buttons])
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
    "Post",
    posts.map(p => {
      let label = match p {
        Drive => "Drive"
        Hull => "Hull"
        Craft => "Craft"
      }
      choice(emit, label, Posted(post=p), pressed=at == Some(p))
    }) +
    (if hand is Some(_) { [choice(emit, "Leave the crew", Left)] } else { [] }),
  )
  guard hand is Some(h) else { [post] }
  let watch = match h.watch {
    Some(_) => [group("Watch", [@html.p("On watch. Changing post breaks it.")])]
    None => {
      let longest = @core.max_watch(h.rank) / @core.HOUR
      let hours : Array[Int64] = [1, 2, 4, 8, 12]
      [
        group(
          "Watch",
          hours
          .filter(n => n <= longest)
          .map(n => {
            choice(
              emit,
              plural(n, "hour", "hours"),
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
  let orders = later.map(phase => {
    posts.map(p => {
      let order : @core.Order = { phase, post: p, }
      choice(
        emit,
        "\{post_name(p)} at the \{phase_name(phase)}",
        Ordered(order=Some(order)),
        pressed=h.order == Some(order),
      )
    })
  })
  let cancel = if h.order is Some(_) {
    [choice(emit, "Cancel the order", Ordered(order=None))]
  } else {
    []
  }
  let order = if later.is_empty() {
    []
  } else {
    [group("Standing order", orders.flatten() + cancel)]
  }
  let crafts : Array[@core.Craft] = [Artist, Engineer]
  let craft = group(
    "Craft",
    crafts.map(k => {
      let label = match k {
        Artist => "Art"
        Engineer => "Engineering"
      }
      choice(emit, label, Crafted(craft=k), pressed=h.craft == k)
    }),
  )
  let refit = if h.craft == Engineer {
    [
      group(
        "Refit",
        @core.refits
        .filter(r => c.fit.can_refit(r))
        .map(r => {
          choice(
            emit,
            refit_name(r),
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
fn view(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  let body = match model.sync {
    Loading => [@html.p("Reaching the ship.")]
    Offline(reason~) => [@html.p("Out of contact with the ship: \{reason}")]
    Ready(sync) => {
      let s = shown(model, sync)
      let away = match model.since {
        Some(was) => news(was, s, model.crew)
        None => []
      }
      let away = if away.is_empty() {
        [@html.li("Nothing new since your last visit.")]
      } else {
        away.map(line => @html.li(line))
      }
      [
        @html.section(
          [@html.h2("Where the ship is"), ..sentences(where_sentences(s))],
        ),
        @html.section([@html.h2("While you were away"), @html.ul(away)]),
        @html.section(
          [@html.h2("You"), ..sentences(you_sentences(s, model.crew))],
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
      ]
    }
  }
  @html.main_(class="checkin", [@html.h1(@ships.flagship().name), ..body])
}

///|
fn main {
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state_with_init(
      init=emit => {
        let since : @core.State? = Some(
          @json.from_json(@json.parse(load_seen())),
        ) catch {
          _ => None
        }
        let model = { crew: crew_id(), now: unix_now(), since, sync: Loading, }
        (model, load(emit))
      },
      update~,
      subscriptions=(_, emit) => {
        @sub.batch([
          @sub.every(TOCK_MS, emit(Tock)),
          @sub.every(POLL_MS, load(emit)),
        ])
      },
    )
    model.view(model => view(model, emit))
  }).mount("app")
}
