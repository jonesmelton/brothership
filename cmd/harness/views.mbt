///|
/// Distances for the envelope sweep, in light-years.
let sweep : Array[Double] = [
  2.0, 3.0, 5.0, 8.0, 12.0, 20.0, 30.0, 45.0, 60.0, 90.0, 120.0, 150.0, 200.0, 300.0,
]

///|
/// Crossing length the design asks for, in hours: `docs/gameplay.md`.
const TARGET_LO : Double = 6.0

///|
const TARGET_HI : Double = 16.0

///|
/// The design's limit on how much staffing may stretch a crossing.
const SPREAD_LIMIT : Double = 2.5

///|
fn ratio(slow : Int64, fast : Int64) -> Double {
  slow.to_double() / fast.to_double()
}

///|
fn two_places(x : Double) -> String {
  let hundredths = (x * 100.0).round().to_int64()
  let frac = hundredths % 100L
  "\{hundredths / 100L}.\{if frac < 10L { "0" } else { "" }}\{frac}"
}

///|
fn envelope_view(route : @sim.Route) -> @html.Html {
  let plan = route.plan()
  let spread = ratio(plan.slowest(), plan.fastest())
  let rows = sweep.map(d => {
    let p = { ..route, distance_ly: d, }.plan()
    (d, p.fastest(), p.slowest())
  })
  let x = {
    lo: @fmath.ln(sweep[0]),
    hi: @fmath.ln(sweep[sweep.length() - 1]),
    from: GUTTER,
    to: WIDTH - 8,
  }
  let top = rows.fold(init=0L, (m, r) => m.max(r.2))
  let y = { lo: 0.0, hi: top.to_double() / 3600.0, from: 190, to: 12, }
  let line = (pick : ((Double, Int64, Int64)) -> Int64) => {
    rows.map(r => (x.at(@fmath.ln(r.0)), y.at(pick(r).to_double() / 3600.0)))
  }
  let last = rows[rows.length() - 1]
  let here = x.at(@fmath.ln(route.distance_ly))
  let marks = [
    @svg.rect(
      x=GUTTER,
      y=y.at(TARGET_HI),
      width=WIDTH - 8 - GUTTER,
      height=y.at(TARGET_LO) - y.at(TARGET_HI),
      fill="#ececec",
    ),
    label(GUTTER - 96, y.at(TARGET_HI) + 14, "target 6–16 h"),
    rule(here, 12, here, 190, stroke=ACCENT),
    label(here + 4, 24, "\{route.distance_ly} ly", fill=ACCENT),
    @svg.polyline(
      points=line(r => r.1),
      fill="none",
      stroke=INK,
      stroke_width=2,
    ),
    @svg.polyline(
      points=line(r => r.2),
      fill="none",
      stroke=INK,
      stroke_width=1,
    ),
    label(WIDTH - 60, y.at(last.1.to_double() / 3600.0) + 14, "fastest"),
    label(WIDTH - 60, y.at(last.2.to_double() / 3600.0) - 6, "slowest"),
    rule(GUTTER, 190, WIDTH - 8, 190),
  ]
  for d in [2.0, 5.0, 20.0, 60.0, 150.0, 300.0] {
    marks.push(label(x.at(@fmath.ln(d)) - 8, 206, "\{d.to_int()}"))
  }
  marks.push(label(GUTTER - 96, 206, "light-years"))
  for h in [0, 24, 48, 72, 96, 120] {
    if h.to_double() <= y.hi {
      marks.push(label(GUTTER - 30, y.at(h.to_double()) + 4, "\{h} h"))
    }
  }
  let within = rows.filter(r => {
    r.2.to_double() / 3600.0 <= TARGET_HI &&
    r.1.to_double() / 3600.0 >= TARGET_LO
  })
  let over = rows.filter(r => ratio(r.2, r.1) > SPREAD_LIMIT)
  @html.section([
    @html.h2("Envelope"),
    @html.p(
      "At \{route.distance_ly} ly every crew arrives between \{hours(plan.fastest())} and \{hours(plan.slowest())} hours: staffing can stretch it \{two_places(spread)}×" +
      (if spread > SPREAD_LIMIT {
        ", over the 2.5× limit."
      } else {
        ", within the 2.5× limit."
      }),
    ),
    figure(
      "Fastest and slowest arrival by distance, γ cap \{grouped(route.gamma_cap.to_int64())}. \{within.length()} of \{rows.length()} distances fall wholly inside 6–16 hours; \{over.length()} exceed the 2.5× spread.",
      214,
      marks,
      data_table(
        "Envelope by distance",
        ["Distance, ly", "Fastest, h", "Slowest, h", "Spread, ×"],
        rows.map(r => {
          [
            r.0.to_int().to_string(),
            hours(r.1),
            hours(r.2),
            two_places(ratio(r.2, r.1)),
          ]
        }),
      ),
    ),
  ])
}

///|
fn histogram_marks(
  values : Array[Int64],
  lo : Int64,
  hi : Int64,
  bins : Int32,
  height : Int32,
) -> Array[@svg.Svg] {
  let counts = @sim.histogram(values, lo~, hi~, bins~)
  let most = counts.fold(init=1, (m, c) => m.max(c))
  let width = (WIDTH - 8 - GUTTER) / bins
  let marks = []
  for i, c in counts {
    let h = c * (height - 20) / most
    marks.push(
      @svg.rect(
        x=GUTTER + i * width,
        y=height - 20 - h,
        width=width - 1,
        height=h,
        fill=INK,
      ),
    )
  }
  marks.push(rule(GUTTER, height - 20, WIDTH - 8, height - 20))
  marks.push(label(GUTTER - 96, 14, "tallest bin \{most}"))
  marks
}

///|
fn batch_view(
  scenario : @sim.Scenario,
  outcomes : Array[@sim.Outcome],
  open : Int64?,
  emit : @rabbita.Emit[Msg],
) -> @html.Html {
  let plan = scenario.route.plan()
  let arrivals = outcomes.map(o => o.arrived_at)
  let min_hulls = outcomes.map(o => o.min_hull)
  let checkins = outcomes.fold(init=0, (n, o) => n + o.checkins)
  let dead = outcomes.fold(init=0, (n, o) => n + o.dead_checkins)
  let live = outcomes.fold(init=0, (n, o) => n + o.live_checkins)
  let per_run = (pick : (@sim.Outcome) -> Int64) => {
    let n = outcomes.length().max(1).to_int64()
    let tenths = outcomes.fold(init=0L, (t, o) => t + pick(o)) * 10L / n
    "\{tenths / 10L}.\{tenths % 10L}"
  }
  let longest = outcomes.map(o => o.longest_dead)
  let total = outcomes.fold(init=0L, (n, o) => {
    n + o.drive_ticks + o.hull_ticks + o.craft_ticks
  })
  let share = (pick : (@sim.Outcome) -> Int64) => {
    percent(outcomes.fold(init=0L, (n, o) => n + pick(o)), total)
  }
  let lo = plan.fastest()
  let hi = plan.slowest()
  let arrival_marks = histogram_marks(arrivals, lo, hi, 24, 120)
  arrival_marks.push(label(GUTTER, 116, hours(lo) + " h fastest"))
  arrival_marks.push(label(WIDTH - 110, 116, hours(hi) + " h slowest"))
  let p50 = @sim.percentile(arrivals, 50)
  let x = x_scale(lo.to_double(), hi.to_double())
  arrival_marks.push(
    rule(x.at(p50.to_double()), 0, x.at(p50.to_double()), 100, stroke=ACCENT),
  )
  arrival_marks.push(
    label(x.at(p50.to_double()) + 4, 12, "median", fill=ACCENT),
  )
  let hull_marks = histogram_marks(min_hulls, 0L, @core.HULL_FULL, 20, 100)
  hull_marks.push(label(GUTTER, 96, "0%"))
  hull_marks.push(label(WIDTH - 40, 96, "100%"))
  let sorted = outcomes.copy()
  sorted.sort_by_key(o => o.arrived_at)
  let picks = if sorted.length() <= 12 {
    sorted
  } else {
    sorted[:6].to_owned() + sorted[sorted.length() - 6:].to_owned()
  }
  @html.section([
    @html.h2("Batch of \{outcomes.length()} runs"),
    @html.p(
      "Median arrival \{hours(p50)} h, 80th percentile \{hours(@sim.percentile(arrivals, 80))} h, latest \{hours(@sim.percentile(arrivals, 100))} h, against an envelope of \{hours(lo)}–\{hours(hi)} h. " +
      "\{percent(dead.to_int64(), checkins.to_int64())} of player check-ins could not move arrival by five minutes. " +
      "Crew time went \{share(o => o.drive_ticks)} to the drive, \{share(o => o.hull_ticks)} to the hull and \{share(o => o.craft_ticks)} to crafts. " +
      "\{percent(live.to_int64(), checkins.to_int64())} of player check-ins offered a real trade: two or more choices that no other choice beat on arrival, hull, works, regard and refits together. " +
      "Per run, crews met \{per_run(o => o.met.to_int64())} demands and missed \{per_run(o => o.missed.to_int64())}, landed \{per_run(o => o.refits)} refit levels and made \{per_run(o => o.work * 10L / @core.WORK_SIZE)} tenths of a work.",
    ),
    figure(
      "Arrival time across the batch, from the fastest to the slowest possible crossing.",
      120,
      arrival_marks,
      data_table(
        "Arrival percentiles",
        ["Percentile", "Arrival, h"],
        [10, 25, 50, 75, 90, 100].map(p => {
          ["\{p}th", hours(@sim.percentile(arrivals, p))]
        }),
      ),
    ),
    figure(
      "Lowest hull reached in each run. Median \{hull_percent(@sim.percentile(min_hulls, 50))}, lowest \{hull_percent(@sim.percentile(min_hulls, 0))}.",
      100,
      hull_marks,
      data_table(
        "Lowest hull percentiles",
        ["Percentile", "Lowest hull"],
        [0, 10, 50, 90].map(p => {
          ["\{p}th", hull_percent(@sim.percentile(min_hulls, p))]
        }),
      ),
    ),
    @html.p(
      "Longest stretch a player went without a check-in that mattered: median \{hours(@sim.percentile(longest, 50))} h, worst \{hours(@sim.percentile(longest, 100))} h.",
    ),
    @html.h3("Fastest and slowest runs"),
    @html.div(
      class="table-scroll",
      attrs=@html.Attrs::build()
        .role("region")
        .aria_label("Fastest and slowest runs")
        .tabindex(0),
      [
        @html.table([
          @html.thead([
            @html.tr([
              @html.th(scope=Col, "Seed"),
              @html.th(scope=Col, class="num", "Arrival, h"),
              @html.th(scope=Col, class="num", "Lowest hull"),
              @html.th(scope=Col, class="num", "Dead check-ins"),
              @html.th(scope=Col, ""),
            ]),
          ]),
          @html.tbody(
            picks.map(o => {
              @html.tr([
                @html.th(scope=Row, o.seed.to_string()),
                @html.td(class="num", hours(o.arrived_at)),
                @html.td(class="num", hull_percent(o.min_hull)),
                @html.td(class="num", "\{o.dead_checkins} of \{o.checkins}"),
                @html.td(
                  if open == Some(o.seed) {
                    @html.text("open")
                  } else {
                    @html.button(
                      on_click=emit(Open(o.seed)),
                      "Open run \{o.seed}",
                    )
                  },
                ),
              ])
            }),
          ),
        ]),
      ],
    ),
  ])
}

///|
/// One track of the run timeline: a labelled band of `height` px at `top`.
fn track(
  top : Int32,
  height : Int32,
  name : String,
  lo : Double,
  hi : Double,
) -> Scale {
  ignore(name)
  { lo, hi, from: top + height, to: top + 4, }
}

///|
fn run_view(
  scenario : @sim.Scenario,
  run : @sim.Run,
  changes_only : Bool,
  emit : @rabbita.Emit[Msg],
) -> @html.Html {
  let plan = run.plan
  let samples = run.samples
  let end = run.arrived_at.to_double()
  let x = x_scale(0.0, end)
  let series = (pick : (@sim.Sample) -> Double) => {
    samples.map(s => (s.t.to_double(), pick(s)))
  }
  let marks = []
  let row = 56
  let names = [
    "phase", "rapidity η", "setting", "hull", "crew", "forecast", "check-ins",
  ]
  for i, name in names {
    marks.push(label(0, i * row + 30, name))
    marks.push(rule(GUTTER, i * row + row - 2, WIDTH - 8, i * row + row - 2))
  }
  // Phase strip.
  for i, s in samples {
    let next = samples.get(i + 1).map(n => n.t).unwrap_or(run.arrived_at)
    if next > s.t && s.phase != Arrived {
      marks.push(
        @svg.rect(
          x=x.at(s.t.to_double()),
          y=12,
          width=(x.at(next.to_double()) - x.at(s.t.to_double())).max(1),
          height=28,
          fill=match s.phase {
            Burn => "#4a4a4a"
            Coast => "#d0d0d0"
            _ => "#7a7a7a"
          },
        ),
      )
    }
    if i == 0 || samples[i - 1].phase != s.phase {
      if s.phase != Arrived {
        marks.push(label(x.at(s.t.to_double()) + 2, 52, phase_name(s.phase)))
      }
    }
  }
  // Rapidity: linear in time aboard while the drive fires.
  let eta = track(row, row - 8, "eta", 0.0, plan.burn.to_double())
  marks.push(
    @svg.polyline(
      points=series(s => s.eta.to_double()).map(p => (x.at(p.0), eta.at(p.1))),
      fill="none",
      stroke=INK,
      stroke_width=2,
    ),
  )
  marks.push(
    label(
      WIDTH / 2,
      row + 14,
      "γ peaks at \{grouped(@sim.gamma(plan.burn).round().to_int64())}",
    ),
  )
  let set = track(2 * row, row - 8, "setting", 0.35, 1.0)
  marks.push(
    @svg.polyline(
      points=step_points(series(s => s.setting.to_double() / 1000.0), x, set),
      fill="none",
      stroke=INK,
      stroke_width=2,
    ),
  )
  let hull = track(3 * row, row - 8, "hull", 0.0, 1.0)
  for band in [0.25, 0.5, 0.75] {
    marks.push(rule(GUTTER, hull.at(band), WIDTH - 8, hull.at(band)))
  }
  marks.push(
    @svg.polyline(
      points=step_points(
        series(s => s.hull.to_double() / @core.HULL_FULL.to_double()),
        x,
        hull,
      ),
      fill="none",
      stroke=INK,
      stroke_width=2,
    ),
  )
  let most = samples.fold(init=1L, (m, s) => {
    m.max(s.drive).max(s.mending).max(s.crafting)
  })
  let crew = track(4 * row, row - 8, "crew", 0.0, most.to_double())
  for
    pick in [
      ("drive", INK, (s : @sim.Sample) => s.drive),
      ("hull", ACCENT, (s : @sim.Sample) => s.mending),
      ("craft", "#8a8a8a", (s : @sim.Sample) => s.crafting),
    ] {
    let (name, color, get) = pick
    let pts = step_points(series(s => get(s).to_double()), x, crew)
    marks.push(
      @svg.polyline(points=pts, fill="none", stroke=color, stroke_width=2),
    )
    let last = pts[pts.length() - 1]
    marks.push(label(last.0 - 36, last.1 - 3, name, fill=color))
  }
  let fc = track(
    5 * row,
    row - 8,
    "forecast",
    plan.fastest().to_double(),
    plan.slowest().to_double(),
  )
  marks.push(
    @svg.polyline(
      points=step_points(series(s => s.forecast.to_double()), x, fc),
      fill="none",
      stroke=INK,
      stroke_width=2,
    ),
  )
  marks.push(
    label(WIDTH - 140, 5 * row + 14, "slowest \{hours(plan.slowest())} h"),
  )
  marks.push(
    label(WIDTH - 140, 6 * row - 12, "fastest \{hours(plan.fastest())} h"),
  )
  for d in run.decisions {
    let px = x.at(d.t.to_double())
    let changed = d.from != Some(d.to)
    let dead = d.leverage < @sim.DEAD_LEVERAGE
    marks.push(
      @svg.line(
        x1=px,
        y1=6 * row + (if changed { 6 } else { 20 }),
        x2=px,
        y2=6 * row + 40,
        stroke=if dead { QUIET } else { INK },
        stroke_width=1,
      ),
    )
  }
  let mut h = 0
  while h.to_double() * 3600.0 <= end {
    marks.push(label(x.at(h.to_double() * 3600.0) - 4, 7 * row + 12, "\{h}"))
    h += if end > 40.0 * 3600.0 { 12 } else { 2 }
  }
  marks.push(label(0, 7 * row + 12, "hours aboard"))
  let changes = run.decisions.filter(d => d.from != Some(d.to))
  let shown = if changes_only { changes } else { run.decisions }
  let capped = shown.length() > 400
  let rows = (if capped { shown[:400].to_owned() } else { shown }).map(d => {
    let (name, policy) = match scenario.actors.get(d.actor) {
      Some(a) => (a.name, a.policy.name())
      None => ("recruit \{d.actor - 999}", "steady")
    }
    [
      clock(d.t),
      name,
      policy,
      "\{d.from.map(post_name).unwrap_or("joins")} → \{post_name(d.to)}",
      if d.watch > 0L {
        hours(d.watch)
      } else {
        "none"
      },
      minutes_delta(d.after - d.before),
      (d.leverage / 60L).to_string(),
      d.undominated.to_string(),
      d.news.to_string(),
    ]
  })
  @html.section([
    @html.h2("Run \{run.seed}"),
    @html.p(
      "Arrived after \{hours(run.arrived_at)} h (envelope \{hours(plan.fastest())}–\{hours(plan.slowest())} h). Hull fell to \{hull_percent(run.min_hull)} and ended at \{hull_percent(run.end_hull)}. \{run.decisions.length()} check-ins, \{changes.length()} of which changed post; \{run.dead_checkins} of \{run.checkins} player check-ins were dead. " +
      demands_sentence(run.last) +
      " " +
      fit_sentence(run.last),
    ),
    figure(
      "Timeline of run \{run.seed}. Phase, rapidity, drive setting, hull with band edges, crew per post, forecast arrival between the fastest and slowest possible, and check-ins: tall ticks changed post, grey ticks could not move arrival by five minutes.",
      7 * row + 18,
      marks,
      data_table(
        "Samples, run \{run.seed}",
        [
          "Time", "Phase", "Setting", "Hull", "Drive", "Hull crew", "Craft", "Forecast, h",
        ],
        samples.map(s => {
          [
            clock(s.t),
            phase_name(s.phase),
            setting(s.setting),
            hull_percent(s.hull),
            s.drive.to_string(),
            s.mending.to_string(),
            s.crafting.to_string(),
            hours(s.forecast),
          ]
        }),
      ),
    ),
    @html.h3("Decisions"),
    @html.label([
      @html.input(
        input_type=Checkbox,
        checked=changes_only,
        on_change=emit.map(_ => ToggleChanges),
      ),
      @html.text(" Only check-ins that changed post"),
    ]),
    data_table(
      "Decisions, run \{run.seed}" +
      (if capped { ", first 400 of \{shown.length()}" } else { "" }),
      [
        "Time", "Crew", "Policy", "Post", "Watch, h", "Arrival change, min", "Leverage, min",
        "Undominated choices", "News",
      ],
      rows,
    ),
  ])
}

///|
fn hazard_name(h : @core.Hazard) -> String {
  match h {
    Breach => "a breach"
    Flare => "a flare"
    Salvage => "salvage"
  }
}

///|
/// What became of the crossing's demands, in order.
fn demands_sentence(c : @core.Crossing) -> String {
  let parts = c.demands.map(d => {
    let phase = phase_name(d.phase)
    let fate = match d.status {
      Met => "met"
      Missed => "missed"
      Open => "still open"
      Waiting => "never opened"
    }
    "\{hazard_name(d.hazard)} in the \{phase}, needing \{hours(d.need / @core.HAND)} crew-hours, \{fate}"
  })
  "Demands: " + parts.join("; ") + "."
}

///|
fn fit_sentence(c : @core.Crossing) -> String {
  let f = c.fit
  let landed = f.baffles +
    f.plating +
    f.injectors +
    f.coils -
    (
      c.ship.fit.baffles +
      c.ship.fit.plating +
      c.ship.fit.injectors +
      c.ship.fit.coils
    )
  let works = c.tallies.values().fold(init=0L, (n, t) => n + t.work)
  "Refit levels landed: \{landed}; the drive now needs \{f.needed} hands. Works made: \{works * 10L / @core.WORK_SIZE} tenths."
}
