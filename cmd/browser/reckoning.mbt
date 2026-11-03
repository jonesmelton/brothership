// The Voyage page's reckoning: the crossing on the ship's clock and the
// worlds', a map of the worlds, and the figures behind both. The figures are
// tables a screen reader can read; the drawings repeat them and are hidden
// from assistive technology. See docs/design.md.

///|
/// Where the turns and the ship fall on the hours aboard, in thousandths
/// sized as the track is, and the Lorentz factor at the top and now.
struct GammaProfile {
  burn_end : Int64
  approach_start : Int64
  now : Int64
  /// The rapidity at the top of the burn, and its Lorentz factor.
  top : Double
  peak : Double
  now_gamma : Double
} derive(Debug)

///|
fn gamma_profile(c : @core.Crossing) -> GammaProfile {
  let st = stretches(c)
  let width = (p : @core.Phase) => {
    st.iter().find_first(s => s.phase == p).map(s => s.width).unwrap_or(0L)
  }
  let now = if c.phase == Arrived {
    1000L
  } else {
    st.fold(init=0L, (n, s) => {
      if s.phase < c.phase {
        n + s.width
      } else if s.phase == c.phase {
        n + s.width * s.done / 1000L
      } else {
        n
      }
    })
  }
  {
    burn_end: width(Burn),
    approach_start: 1000L - width(Approach),
    now,
    top: c.plan.burn.to_double() / 1.0e9,
    peak: @ships.gamma(c.plan.burn),
    now_gamma: @ships.reckon(c).gamma(),
  }
}

///|
/// A height on the chart for a Lorentz factor, between one at the base and
/// the crossing's peak at the top.
fn chart_y(gamma : Double, peak : Double) -> Int64 {
  guard peak > 1.0 else { return PROFILE_BASE }
  let share = (gamma - 1.0) / (peak - 1.0)
  (PROFILE_BASE.to_double() - share * (PROFILE_BASE - PROFILE_TOP).to_double())
  .round()
  .to_int64()
}

///|
/// Samples across each burn. The curve turns sharply near the top, so the
/// samples are close enough there that the polyline reads as a curve.
const BURN_SAMPLES : Int32 = 48

///|
/// The Lorentz factor over the hours aboard as a polyline. Rapidity rises
/// in step with the burn's hours, so γ = cosh(η) stays near one for most of
/// the burn and climbs to the peak in its last stretch; the approach is the
/// mirror of it.
fn gamma_curve(g : GammaProfile) -> Array[(Int64, Int64)] {
  let ys = Array::makei(BURN_SAMPLES + 1, k => {
    let f = k.to_double() / BURN_SAMPLES.to_double()
    chart_y(@cmath.cosh(g.top * f), g.peak)
  })
  let n = BURN_SAMPLES.to_int64()
  let rise = ys.mapi((k, y) => (g.burn_end * k.to_int64() / n, y))
  let fall = ys.mapi((k, _) => {
    let x = g.approach_start + (1000L - g.approach_start) * k.to_int64() / n
    (x, ys[BURN_SAMPLES - k])
  })
  [..rise, ..fall]
}

///|
/// A polyline cut at `x`: the part before, and the part after, each ending
/// or starting at the cut.
fn split_profile(
  points : Array[(Int64, Int64)],
  x : Int64,
) -> (Array[(Int64, Int64)], Array[(Int64, Int64)]) {
  let before = []
  let after = []
  for i, p in points {
    if p.0 <= x {
      before.push(p)
    }
    if i + 1 < points.length() {
      let q = points[i + 1]
      if p.0 < x && x < q.0 {
        let y = p.1 + (q.1 - p.1) * (x - p.0) / (q.0 - p.0)
        before.push((x, y))
        after.push((x, y))
      }
    }
    if p.0 >= x {
      after.push(p)
    }
  }
  (before, after)
}

///|
/// The drawing's height in viewBox units: the profile's base and top.
const PROFILE_TOP : Int64 = 10

///|
const PROFILE_BASE : Int64 = 400

///|
fn points(ps : Array[(Int64, Int64)]) -> Array[(Int32, Int32)] {
  ps.map(p => (p.0.to_int(), p.1.to_int()))
}

///|
/// One end of a scale: what it counts, and its length.
fn scale_label(what : String, total : String) -> @rabbita.Html {
  @html.div(class="scale", [
    @html.span(class="label", what),
    @html.span(class="total", total),
  ])
}

///|
/// The Lorentz factor over the hours aboard: one at departure, climbing to
/// the coast's peak at the end of the burn, and back to one at arrival. The
/// ship is an HTML dot over the drawing, so the stretched drawing does not
/// stretch it.
fn gamma_figure(c : @core.Crossing) -> @rabbita.Html {
  let g = gamma_profile(c)
  let (flown, ahead) = split_profile(gamma_curve(g), g.now)
  let now_y = chart_y(g.now_gamma, g.peak)
  let svg = @svg.svg(
    view_box="0 0 1000 \{PROFILE_BASE}",
    attrs=@svg.Attrs::build().preserve_aspect_ratio("none"),
    [
      @svg.line(
        class="axis",
        x1=0,
        y1=PROFILE_BASE.to_int(),
        x2=1000,
        y2=PROFILE_BASE.to_int(),
      ),
      @svg.line(
        class="peak",
        x1=0,
        y1=PROFILE_TOP.to_int(),
        x2=1000,
        y2=PROFILE_TOP.to_int(),
      ),
      @svg.polyline(class="ahead", points=points(ahead)),
      @svg.polyline(class="flown", points=points(flown)),
      @svg.line(
        class="now",
        x1=g.now.to_int(),
        y1=PROFILE_BASE.to_int(),
        x2=g.now.to_int(),
        y2=now_y.to_int(),
      ),
    ],
  )
  let left = "\{g.now / 10L}.\{g.now % 10L}%"
  let top = now_y * 1000L / PROFILE_BASE
  let dot = @html.span(
    class="dot",
    style=["left: \{left}", "top: \{top / 10L}.\{top % 10L}%"],
    "",
  )
  let hours = c.forecast().map(t => t.to_double() / 3600.0)
  @html.div(class="chart", attrs=@html.Attrs::build().aria_hidden("true"), [
    scale_label(
      "Lorentz factor γ",
      "\{@words.figure(g.peak, 0)} on the coast, \{@words.figure(g.now_gamma, 0)} now",
    ),
    @html.div(class="plot", [svg, dot]),
    scale_label(
      "Hours aboard",
      hours.map(h => "\{@words.figure(h, 1)} h").unwrap_or(""),
    ),
  ])
}

///|
/// How the map turns light-years in the worlds' plane into viewBox units:
/// a thousand across, north up.
struct MapFrame {
  left : Double
  top : Double
  scale : Double
  height : Int64
}

///|
/// Light-years of margin around the worlds; more above, for the names.
const MAP_SIDE : Double = 4.5

///|
const MAP_ABOVE : Double = 5.0

///|
const MAP_BELOW : Double = 2.5

///|
fn map_frame() -> MapFrame {
  let ps = @ships.worlds.map(w => w.on_map())
  ps.push(@ships.on_map((0.0, 0.0, 0.0)))
  let xs = ps.map(p => p.0)
  let ys = ps.map(p => p.1)
  let min = (a : Array[Double]) => a.fold(init=a[0], (m, x) => m.min(x))
  let max = (a : Array[Double]) => a.fold(init=a[0], (m, x) => m.max(x))
  let left = min(xs) - MAP_SIDE
  let width = max(xs) + MAP_SIDE - left
  let top = max(ys) + MAP_ABOVE
  let scale = 1000.0 / width
  let height = ((top - min(ys) + MAP_BELOW) * scale).round().to_int64()
  { left, top, scale, height, }
}

///|
fn MapFrame::place(self : MapFrame, p : (Double, Double)) -> (Int64, Int64) {
  (
    ((p.0 - self.left) * self.scale).round().to_int64(),
    ((self.top - p.1) * self.scale).round().to_int64(),
  )
}

///|
/// Where the ship is on the map: the share of the leg from `from` to `to`
/// run, along it.
fn ship_on_map(
  c : @core.Crossing,
  from : @ships.World,
  to : @ships.World,
) -> (Double, Double) {
  let r = @ships.reckon(c)
  let f = r.run / r.length
  let (fx, fy) = from.on_map()
  let (tx, ty) = to.on_map()
  (fx + (tx - fx) * f, fy + (ty - fy) * f)
}

///|
/// Where a ship in the fleet list is on the map: the share of its leg it has
/// run, along it, or at its world in port.
fn listing_on_map(l : @core.Listing) -> (Double, Double) {
  guard @ships.world_named(l.from) is Some(from) else { (0.0, 0.0) }
  guard l.bound.bind(@ships.world_named) is Some(to) else { from.on_map() }
  let f = (l.run.to_double() / 1000.0).max(0.0).min(1.0)
  let (fx, fy) = from.on_map()
  let (tx, ty) = to.on_map()
  (fx + (tx - fx) * f, fy + (ty - fy) * f)
}

///|
/// The pairs of worlds some other ship is bound between, each pair once in
/// whichever order it first appears. The player's own leg is drawn apart,
/// so a pair it shares is left out.
fn voyage_lanes(
  fleet : Array[@core.Listing],
  own : String?,
) -> Array[(String, String)] {
  let same = (a : (String, String), b : (String, String)) => {
    a == b || (a.1, a.0) == b
  }
  let own_leg = fleet
    .iter()
    .find_first(l => own == Some(l.id))
    .bind(l => l.bound.map(to => (l.from, to)))
  let lanes = []
  for l in fleet {
    guard own != Some(l.id) && l.bound is Some(to) else { continue }
    let lane = (l.from, to)
    if own_leg is Some(o) && same(o, lane) {
      continue
    }
    if !lanes.iter().any(m => same(m, lane)) {
      lanes.push(lane)
    }
  }
  lanes
}

///|
/// The worlds in their plane, the lanes other ships are bound along, the
/// fleet's ships and the leg under way, and the Sun, which lies 7.6 ly off
/// the plane.
fn map_figure(
  s : @core.State,
  fleet : Array[@core.Listing],
  own : String?,
) -> @rabbita.Html {
  let frame = map_frame()
  let ws = @ships.worlds
  let at = (p : (Double, Double)) => {
    let (x, y) = frame.place(p)
    (x.to_int(), y.to_int())
  }
  let segment = (class : String, a : (Double, Double), b : (Double, Double)) => {
    let (x1, y1) = at(a)
    let (x2, y2) = at(b)
    @svg.line(class~, x1~, y1~, x2~, y2~)
  }
  let dot = (class : String, p : (Double, Double), r : Int32) => {
    let (cx, cy) = at(p)
    @svg.circle(class~, cx~, cy~, r~)
  }
  let lanes = voyage_lanes(fleet, own).filter_map(lane => {
    let (a, b) = lane
    match (@ships.world_named(a), @ships.world_named(b)) {
      (Some(a), Some(b)) => Some(segment("lane", a.on_map(), b.on_map()))
      _ => None
    }
  })
  let place = (
    p : (Double, Double),
    class : String,
    label : Array[@rabbita.Html],
  ) => {
    let (x, y) = frame.place(p)
    let left = "\{x / 10L}.\{x % 10L}%"
    let top = "\{y * 1000L / frame.height / 10L}.\{y * 1000L / frame.height % 10L}%"
    @html.span(
      class="place \{class}",
      style=["left: \{left}", "top: \{top}"],
      label,
    )
  }
  let offsets : Array[(Double, Double)] = [
    (12.0, -8.0),
    (-12.0, -8.0),
    (12.0, 10.0),
    (-12.0, 10.0),
  ]
  let others = fleet
    .filter(l => own != Some(l.id))
    .mapi((i, l) => {
      let (dx, dy) = offsets[i % offsets.length()]
      let (x, y) = listing_on_map(l)
      let p = (x + dx / frame.scale, y + dy / frame.scale)
      let pennant = @ships.profile_named(l.name)
        .bind(profile => profile.title)
        .map(title => title.pennant)
        .unwrap_or(l.name)
      (p, place(p, "other", [@html.span(class="star", pennant)]), l.name)
    })
  let from = @ships.origin(s.ship)
  let leg = match (s.crossing(), @ships.bound_for(s)) {
    (Some(c), Some(to)) => {
      let ship = ship_on_map(c, from, to)
      [
        segment("flown", from.on_map(), ship),
        segment("ahead", ship, to.on_map()),
        dot("ship", ship, 9),
      ]
    }
    (None, Some(to)) => [segment("ahead", from.on_map(), to.on_map())]
    // In port before the ship chooses, no leg is drawn.
    (_, None) => []
  }
  let sun = @ships.on_map((0.0, 0.0, 0.0))
  let svg = @svg.svg(
    view_box="0 0 1000 \{frame.height}",
    [
      ..lanes,
      ..ws.map(w => dot("world", w.on_map(), 8)),
      ..others.map(o => {
        let (cx, cy) = at(o.0)
        // A cast ship is drawn in its accent; any other keeps the hollow dot.
        @svg.circle(class="other", style=accent_style(o.2), cx~, cy~, r=8)
      }),
      dot("sun", sun, 6),
      ..leg,
    ],
  )
  let names = ws.map(w => {
    place(w.on_map(), "world", [
      @html.span(class="name", w.name),
      @html.span(class="star", w.star),
    ])
  })
  @html.div(
    class="map",
    style=["aspect-ratio: 1000 / \{frame.height}"],
    attrs=@html.Attrs::build().aria_hidden("true"),
    [
      svg,
      ..names,
      ..others.map(o => o.1),
      place(sun, "sun", [@html.span(class="star", "Sun")]),
    ],
  )
}

///|
/// The fleet seen from aboard: the star map, and a sentence for every ship
/// but this one. A ship's log is its own while the player is aboard it.
fn fleet_section(
  model : Model,
  s : @core.State,
  fleet : Array[@core.Listing],
) -> @rabbita.Html {
  let others = fleet.filter(l => model.ship != Some(l.id))
  let lines = if others.is_empty() {
    [@html.p("No other ships are in service.")]
  } else {
    others.map(l => @html.p(@words.fleet_sentence(l, now=model.now)))
  }
  @html.div(
    class="section",
    [@html.h3("The fleet"), ..lines, map_figure(s, fleet, model.ship)],
  )
}

///|
/// Label and figure pairs as a table, one row each.
fn figures(caption : String, rows : Array[(String, String)]) -> @rabbita.Html {
  @html.table(class="figures", [
    @html.caption(caption),
    @html.tbody(
      rows.map(r => @html.tr([@html.th(scope=Row, r.0), @html.td(r.1)])),
    ),
  ])
}

///|
/// The Voyage page's reckoning: underway, the speed over the voyage and the
/// figures behind it, with the bow sight among the instruments; in port, the
/// leg the ship departs on next. The star map is in the fleet section.
fn reckoning_section(s : @core.State) -> @rabbita.Html {
  let body = match s.crossing() {
    Some(c) => {
      let instruments = @words.instrument_rows(s)
      [
        gamma_figure(c),
        figures("The crossing", @words.reckoning_rows(s)),
        ..if instruments.is_empty() {
          []
        } else {
          [
            figures("Instruments", instruments),
            sky_figure(@ships.reckon(c).eta, c.plan.burn.to_double() / 1.0e9),
          ]
        },
      ]
    }
    None => [figures("Next leg", @words.next_leg_rows(s))]
  }
  @html.div(class="section", [
    @html.details([@html.summary("Instruments and reckoning"), ..body]),
  ])
}
