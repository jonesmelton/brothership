///|
struct Model {
  scenario : Int32
  route : @sim.Route
  hull_pct : Int32
  runs : Int32
  outcomes : Array[@sim.Outcome]
  run : @sim.Run?
  changes_only : Bool
  /// Parameters changed since the batch last ran.
  stale : Bool
} derive(Eq)

///|
enum Msg {
  Pick(String)
  Distance(String)
  Cap(String)
  Accel(String)
  Needed(String)
  Wear(String)
  Repair(String)
  Hull(String)
  Runs(String)
  Open(Int64)
  ToggleChanges
  Run
}

///|
fn Model::scenario(self : Model) -> @sim.Scenario {
  {
    ..@sim.scenarios()[self.scenario],
    route: self.route,
    hull: self.hull_pct.to_int64() * @core.HULL_FULL / 100L,
  }
}

///|
/// Rerun the batch and open its median run.
fn Model::refresh(self : Model) -> Model {
  let s = self.scenario()
  let outcomes = s.batch(runs=self.runs)
  let sorted = outcomes.copy()
  sorted.sort_by_key(o => o.arrived_at)
  let run = sorted.get(sorted.length() / 2).map(o => s.run(o.seed))
  { ..self, outcomes, run, stale: false, }
}

///|
fn Model::pick(self : Model, i : Int32) -> Model {
  let s = @sim.scenarios()[i]
  {
    ..self,
    scenario: i,
    route: s.route,
    hull_pct: (s.hull * 100L / @core.HULL_FULL).to_int(),
  }.refresh()
}

///|
fn number(text : String, fallback : Double) -> Double {
  @string.parse_double(text) catch {
    _ => fallback
  }
}

///|
fn whole(text : String, fallback : Int64) -> Int64 {
  @string.parse_int64(text) catch {
    _ => fallback
  }
}

///|
fn update(model : Model, msg : Msg) -> Model {
  let r = model.route
  let set = (route : @sim.Route) => { ..model, route, stale: true, }
  match msg {
    Pick(i) => model.pick(whole(i, 0L).to_int())
    Distance(v) =>
      set({
        ..r,
        distance_ly: number(v, r.distance_ly).clamp(min=0.5, max=1000.0),
      })
    Cap(v) =>
      set({
        ..r,
        gamma_cap: number(v, r.gamma_cap).clamp(min=2.0, max=100000.0),
      })
    Accel(v) =>
      set({
        ..r,
        accel_g: number(v, r.accel_g).clamp(min=1000.0, max=200000.0),
      })
    Needed(v) =>
      set({
        ..r,
        drive_needed: whole(v, r.drive_needed).clamp(min=1L, max=64L),
      })
    Wear(v) =>
      set({ ..r, wear: whole(v, r.wear).clamp(min=0L, max=1_000_000L), })
    Repair(v) =>
      set({ ..r, repair: whole(v, r.repair).clamp(min=0L, max=1_000_000L), })
    Hull(v) =>
      {
        ..model,
        stale: true,
        hull_pct: whole(v, model.hull_pct.to_int64())
        .clamp(min=0L, max=100L)
        .to_int(),
      }
    Runs(v) =>
      {
        ..model,
        stale: true,
        runs: whole(v, model.runs.to_int64()).clamp(min=1L, max=2000L).to_int(),
      }
    Run => model.refresh()
    Open(seed) => { ..model, run: Some(model.scenario().run(seed)), }
    ToggleChanges => { ..model, changes_only: !model.changes_only, }
  }
}

///|
fn field(
  name : String,
  value : String,
  emit : @rabbita.Emit[Msg],
  to_msg : (String) -> Msg,
) -> @html.Html {
  @html.label(class="field", [
    @html.span(name),
    @html.input(input_type=Number, value~, on_change=emit.map(to_msg)),
  ])
}

///|
fn controls(model : Model, emit : @rabbita.Emit[Msg]) -> @html.Html {
  let r = model.route
  @html.form(class="controls", [
    @html.label(class="field", [
      @html.span("Scenario"),
      @html.select(
        on_change=emit.map(v => Pick(v)),
        @sim.scenarios().mapi((i, s) => {
          @html.option(
            value=i.to_string(),
            selected=i == model.scenario,
            s.name,
          )
        }),
      ),
    ]),
    field("Distance, ly", r.distance_ly.to_string(), emit, v => Distance(v)),
    field("γ cap", r.gamma_cap.to_string(), emit, v => Cap(v)),
    field("Acceleration, g", r.accel_g.to_string(), emit, v => Accel(v)),
    field("Drive hands for full burn", r.drive_needed.to_string(), emit, v => {
      Needed(v)
    }),
    field("Wear per second at full burn", r.wear.to_string(), emit, v => Wear(v)),
    field("Repair per hand per second", r.repair.to_string(), emit, v => {
      Repair(v)
    }),
    field("Hull at departure, %", model.hull_pct.to_string(), emit, v => Hull(v)),
    field("Runs in batch", model.runs.to_string(), emit, v => Runs(v)),
    @html.button(
      type_="button",
      on_click=emit(Run),
      if model.stale {
        "Run batch"
      } else {
        "Run again"
      },
    ),
  ])
}

///|
fn crew_view(scenario : @sim.Scenario) -> @html.Html {
  let players = scenario.actors.filter(a => a.is_player()).length()
  @html.p(
    "Crew: \{players} players and \{scenario.actors.length() - players} NPCs. " +
    scenario.actors
    .map(a => {
      let when = match a.cadence {
        Reactive => "reacts to every change"
        Every(every~, ..) if every < 3600L =>
          "checks in every \{every / 60L} min"
        Every(every~, jitter~) =>
          "checks in every \{hours(every)} ± \{hours(jitter)} h"
      }
      let joins = if a.joins_at > 0L {
        ", joins at \{hours(a.joins_at)} h"
      } else {
        ""
      }
      "\{a.name} (\{a.policy.name()}, \{when}\{joins})"
    })
    .join("; ") +
    ".",
  )
}

///|
fn view(model : Model, emit : @rabbita.Emit[Msg]) -> @html.Html {
  let scenario = model.scenario()
  @html.main_(class="sim", [
    @html.h1("Crossing simulator"),
    @html.p(
      "One crossing, drive and hull only. Every run uses the game's own rules from core; seeds replay exactly.",
    ),
    controls(model, emit),
    crew_view(scenario),
    envelope_view(model.route),
    if model.stale {
      @html.p("Parameters changed. Run the batch to see the new results.")
    } else {
      @html.text("")
    },
    batch_view(scenario, model.outcomes, model.run.map(r => r.seed), emit),
    match model.run {
      Some(run) => run_view(scenario, run, model.changes_only, emit)
      None => @html.text("")
    },
  ])
}

///|
fn main {
  let init = {
    scenario: 0,
    route: @sim.Route::default(),
    hull_pct: 100,
    runs: 50,
    outcomes: [],
    run: None,
    changes_only: true,
    stale: false,
  }.pick(1)
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_pure_state(init, update~)
    model.view(model => view(model, emit))
  }).mount("app")
}
