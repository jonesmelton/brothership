// The Voyage page's reckoning: the crossing on the ship's clock and the
// worlds', a map of the worlds, and the figures behind both. The figures are
// tables a screen reader can read; the drawings repeat them and are hidden
// from assistive technology. See docs/visual-design.md.

///|
/// Where the turns of a crossing and the ship fall on one clock, in
/// thousandths of the crossing.
struct Scale {
  burn_end : Int64
  approach_start : Int64
  now : Int64
} derive(Debug, Eq)

///|
/// The crossing on two clocks: hours aboard, sized as the track is, and
/// years at the worlds.
struct Nomogram {
  aboard : Scale
  worlds : Scale
} derive(Debug, Eq)

///|
fn nomogram(c : @core.Crossing) -> Nomogram {
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
  let r = @ships.reckon(c)
  let share = (years : Double) => (years / r.span * 1000.0).round().to_int64()
  let burn = share(r.burn_span)
  {
    aboard: {
      burn_end: width(Burn),
      approach_start: 1000L - width(Approach),
      now,
    },
    worlds: {
      burn_end: burn,
      approach_start: 1000L - burn,
      now: share(r.years),
    },
  }
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
/// The drawing's height in viewBox units: the profile's base, and the
/// worlds' axis below it.
const PROFILE_TOP : Int64 = 6

///|
const PROFILE_BASE : Int64 = 90

///|
const WORLDS_AXIS : Int64 = 150

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
/// The crossing's rapidity over hours aboard, a ramp, a plateau and a ramp
/// down, with each turn and the ship carried down to where it falls in the
/// worlds' years. The burns that take hours aboard are a sliver of the years.
fn nomogram_figure(c : @core.Crossing) -> @rabbita.Html {
  let n = nomogram(c)
  let a = n.aboard
  let profile : Array[(Int64, Int64)] = [
    (0, PROFILE_BASE),
    (a.burn_end, PROFILE_TOP),
    (a.approach_start, PROFILE_TOP),
    (1000, PROFILE_BASE),
  ]
  let (flown, ahead) = split_profile(profile, a.now)
  let link = (class : String, top : Int64, bottom : Int64) => {
    @svg.line(
      class~,
      x1=top.to_int(),
      y1=PROFILE_BASE.to_int(),
      x2=bottom.to_int(),
      y2=WORLDS_AXIS.to_int(),
    )
  }
  let axis = (y : Int64) => {
    @svg.line(class="axis", x1=0, y1=y.to_int(), x2=1000, y2=y.to_int())
  }
  let r = @ships.reckon(c)
  let hours = c.forecast().map(t => t.to_double() / 3600.0)
  let svg = @svg.svg(
    view_box="0 0 1000 \{WORLDS_AXIS}",
    attrs=@svg.Attrs::build().preserve_aspect_ratio("none"),
    [
      axis(PROFILE_BASE),
      axis(WORLDS_AXIS),
      link("turn", a.burn_end, n.worlds.burn_end),
      link("turn", a.approach_start, n.worlds.approach_start),
      @svg.polyline(class="ahead", points=points(ahead)),
      @svg.polyline(class="flown", points=points(flown)),
      // From the ship on the profile, down to both clocks.
      @svg.polyline(
        class="now",
        points=points([
          flown.last().unwrap_or((a.now, PROFILE_BASE)),
          (a.now, PROFILE_BASE),
          (n.worlds.now, WORLDS_AXIS),
        ]),
      ),
    ],
  )
  @html.div(class="nomogram", attrs=@html.Attrs::build().aria_hidden("true"), [
    scale_label(
      "Rapidity, by hours aboard",
      hours.map(h => "\{@words.figure(h, 1)} h").unwrap_or(""),
    ),
    svg,
    scale_label("Years at the worlds", "\{@words.figure(r.span, 2)} years"),
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
/// Where the ship is on the map: the share of the leg run, along it.
fn ship_on_map(c : @core.Crossing, crossings : Int64) -> (Double, Double) {
  let (from, to) = @ships.leg(crossings)
  let r = @ships.reckon(c)
  let f = r.run / r.length
  let (fx, fy) = from.on_map()
  let (tx, ty) = to.on_map()
  (fx + (tx - fx) * f, fy + (ty - fy) * f)
}

///|
/// The worlds in their plane, every lane between them, the leg under way
/// and the ship on it, and the Sun, which lies 7.6 ly off the plane.
fn map_figure(s : @core.State) -> @rabbita.Html {
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
  let lanes = []
  for i in 0..<ws.length() {
    for j in (i + 1)..<ws.length() {
      lanes.push(segment("lane", ws[i].on_map(), ws[j].on_map()))
    }
  }
  let (from, to) = @ships.leg(s.ship.crossings)
  let leg = match s.crossing() {
    Some(c) => {
      let ship = ship_on_map(c, s.ship.crossings)
      [
        segment("flown", from.on_map(), ship),
        segment("ahead", ship, to.on_map()),
        dot("ship", ship, 9),
      ]
    }
    None => [segment("ahead", from.on_map(), to.on_map())]
  }
  let sun = @ships.on_map((0.0, 0.0, 0.0))
  let svg = @svg.svg(
    view_box="0 0 1000 \{frame.height}",
    [
      ..lanes,
      ..ws.map(w => dot("world", w.on_map(), 8)),
      dot("sun", sun, 6),
      ..leg,
    ],
  )
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
    [svg, ..names, place(sun, "sun", [@html.span(class="star", "Sun")])],
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
/// The Voyage page's reckoning: underway, the two clocks, the map and the
/// figures; in port, the map and the leg the ship departs on next.
fn reckoning_section(s : @core.State) -> @rabbita.Html {
  let body = match s.crossing() {
    Some(c) => {
      let instruments = @words.instrument_rows(s)
      [
        nomogram_figure(c),
        figures("The crossing", @words.reckoning_rows(s)),
        ..if instruments.is_empty() {
          []
        } else {
          [figures("Instruments", instruments)]
        },
        map_figure(s),
      ]
    }
    None => [map_figure(s), figures("Next leg", @words.next_leg_rows(s))]
  }
  @html.section([
    @html.details([@html.summary("Instruments and reckoning"), ..body]),
  ])
}
