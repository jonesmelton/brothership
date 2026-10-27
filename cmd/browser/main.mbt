///|
/// Client state. Rendering reads `predicted()`, which already includes
/// proposals the server has not answered yet.
enum Model {
  Loading
  Ready(@core.Optimistic)
  Offline(reason~ : String)
} derive(Eq)

///|
enum Msg {
  Loaded(Result[@core.Snapshot, Error])
  Propose(@core.Event)
  Settled(Result[@core.Receipt, Error])
}

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
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match (model, msg) {
    (Ready(sync), Loaded(Ok(snapshot))) =>
      (Ready(sync.resync(snapshot)), @rabbita.none)
    (_, Loaded(Ok(snapshot))) =>
      (Ready(@core.Optimistic::new(snapshot)), @rabbita.none)
    (_, Loaded(Err(err))) => (Offline(reason=err.to_string()), @rabbita.none)
    (Ready(sync), Propose(event)) =>
      try sync.propose(event) catch {
        // Refused locally: the server would refuse it too.
        _ => (model, @rabbita.none)
      } noraise {
        (next, _) => (Ready(next), send_next(emit, sync, next))
      }
    (Ready(sync), Settled(Ok(receipt))) => {
      let next = sync.settle(receipt)
      (Ready(next), send_next(emit, sync, next))
    }
    // The in-flight proposal's fate is unknown; drop local guesses and settle
    // to whatever the server has.
    (Ready(sync), Settled(Err(_))) =>
      (Ready(@core.Optimistic::new(sync.confirmed())), load(emit))
    (_, Propose(_) | Settled(_)) => (model, @rabbita.none)
  }
}

///|
fn view(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  @html.main_(
    match model {
      Loading => []
      Offline(reason~) => [@html.p("Offline: \{reason}")]
      Ready(sync) =>
        [
          @html.output("\{sync.predicted().clock}"),
          @html.button(
            on_click=emit(Propose(Elapsed(ticks=1))),
            "Elapse one tick",
          ),
        ]
    },
  )
}

///|
fn main {
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state_with_init(
      init=emit => (Loading, load(emit)),
      update~,
    )
    model.view(model => view(model, emit))
  }).mount("app")
}
