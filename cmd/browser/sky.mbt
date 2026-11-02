// The bow sight: the sky ahead as the ship sees it. Rendering only, so it
// works in floats. See docs/design.md.
//
// A direction θ from the bow is drawn at a radius set by u = ln tan(θ/2).
// Aberration at rapidity η is tan(θ'/2) = e^-η tan(θ/2), which on that scale
// is u' = u - η: the whole sky slides toward the bow by η and keeps its
// shape. What the worlds call the forward half of the sky, u < 0, is inside
// u' = -η, the ring the reckoning's cone measures.

///|
/// `ln tan(θ/2)` for a direction whose cosine from the bow is `cos`: below
/// zero ahead of abeam, above it behind.
fn sky_u(cos : Double) -> Double {
  0.5 * @cmath.ln((1.0 - cos) / (1.0 + cos))
}

///|
/// The angle from the bow, in degrees, of a direction at `u`.
fn sky_angle(u : Double) -> Double {
  2.0 * @cmath.atan(@cmath.exp(u)) * 180.0 / @cmath.PI
}

///|
/// The sight's span of `u`, fixed for a crossing so the field's motion over
/// the voyage reads: the stern edge a little behind abeam's rest place, the
/// bow edge a little inside abeam at the crossing's top speed.
struct SkyScale {
  lo : Double
  hi : Double
}

///|
const SKY_MARGIN : Double = 3.0

///|
fn SkyScale::new(peak : Double) -> SkyScale {
  { lo: -peak.max(0.0) - SKY_MARGIN, hi: SKY_MARGIN, }
}

///|
/// The share of the sight's radius at which `u` falls, or `None` off it.
fn SkyScale::radius(self : SkyScale, u : Double) -> Double? {
  if u < self.lo || u > self.hi {
    None
  } else {
    Some((u - self.lo) / (self.hi - self.lo))
  }
}

///|
/// A star as the worlds see it: where it is from the bow, its bearing round
/// the bow in radians, and its drawn size in viewBox units.
struct SkyStar {
  u : Double
  bearing : Double
  size : Double
}

///|
const SKY_STARS : Int32 = 260

///|
/// A fraction in [0, 1) from `x`, the same on every call.
fn scatter(x : Double) -> Double {
  let v = @cmath.sin(x * 12.9898 + 78.233) * 43758.5453
  v - v.floor()
}

///|
/// The same star field on every render: directions spread evenly over the
/// sphere, and a few stars much brighter than the rest.
fn sky_stars() -> Array[SkyStar] {
  Array::makei(SKY_STARS, i => {
    let x = i.to_double()
    let cos = 1.0 - 2.0 * scatter(x + 0.1)
    let bright = scatter(x + 0.7)
    {
      u: sky_u(cos.max(-0.999999).min(0.999999)),
      bearing: 2.0 * @cmath.PI * scatter(x + 0.4),
      size: 2.5 + 7.0 * bright * bright * bright * bright * bright * bright,
    }
  })
}

///|
const SKY_CENTER : Double = 500.0

///|
const SKY_RADIUS : Double = 470.0

///|
/// Rings at round angles from the bow, as `(degrees, label)`.
let sky_rings : Array[(Double, String)] = [
  (90.0, "90°"),
  (1.0, "1°"),
  (1.0 / 60.0, "1′"),
  (1.0 / 3600.0, "1″"),
  (0.01 / 3600.0, "0.01″"),
]

///|
/// The bow sight for a ship at rapidity `eta` on a crossing whose top is
/// `peak`. The drawing is aria-hidden; the Instruments row is the reading.
fn sky_figure(eta : Double, peak : Double) -> @rabbita.Html {
  let scale = SkyScale::new(peak)
  let at = (share : Double, bearing : Double) => {
    let r = share * SKY_RADIUS
    (
      (SKY_CENTER + r * @cmath.sin(bearing)).round().to_int(),
      (SKY_CENTER - r * @cmath.cos(bearing)).round().to_int(),
    )
  }
  let px = (share : Double) => (share * SKY_RADIUS).round().to_int()
  let stars = []
  for star in sky_stars() {
    if scale.radius(star.u - eta) is Some(share) {
      let (cx, cy) = at(share, star.bearing)
      stars.push(
        @svg.circle(class="star", cx~, cy~, r=star.size.round().to_int()),
      )
    }
  }
  let rings = []
  let labels = []
  for ring in sky_rings {
    let (degrees, label) = ring
    let u = @cmath.ln(@cmath.tan(degrees * @cmath.PI / 360.0))
    // A ring too close to the bow would sit under its cross.
    if scale.radius(u) is Some(share) && share >= 0.08 {
      rings.push(@svg.circle(class="ring", cx=500, cy=500, r=px(share)))
      let top = (1000 - (SKY_CENTER + share * SKY_RADIUS).round().to_int()) / 10
      labels.push(@html.span(class="mark", style=["top: \{top}%"], label))
    }
  }
  let half = match scale.radius(-eta) {
    Some(share) => [@svg.circle(class="half", cx=500, cy=500, r=px(share))]
    None => []
  }
  let svg = @svg.svg(
    view_box="0 0 1000 1000",
    [
      @svg.circle(class="rim", cx=500, cy=500, r=SKY_RADIUS.to_int()),
      ..rings,
      ..stars,
      ..half,
      @svg.line(class="cross", x1=480, y1=500, x2=520, y2=500),
      @svg.line(class="cross", x1=500, y1=480, x2=500, y2=520),
    ],
  )
  let cone = sky_angle(-eta) * 3600.0
  @html.figure(class="bow", attrs=@html.Attrs::build().aria_hidden("true"), [
    scale_label(
      "The sky ahead, log scale",
      "half within \{@words.angle_figure(cone)}",
    ),
    @html.div(class="sight", [svg, ..labels]),
  ])
}
