///|
/// A settled world, placed where its star is. Worlds are mutually at rest,
/// so time passes alike at all of them, and none keeps a clock the game
/// reads. See research/liveship-travel-math.md, section 8.
pub(all) struct World {
  name : String
  /// The star it circles, as astronomers name it.
  star : String
  /// The star's J2000 position as seen from the Sun: right ascension in
  /// hours, declination in degrees and distance in light-years.
  ra : Double
  dec : Double
  distance_ly : Double
} derive(Debug, Eq)

///|
fn hours(h : Double, m : Double, s : Double) -> Double {
  h + m / 60.0 + s / 3600.0
}

///|
/// Degrees, minutes and seconds south when `south`.
fn degrees(d : Double, m : Double, s : Double, south~ : Bool) -> Double {
  let v = d + m / 60.0 + s / 3600.0
  if south {
    -v
  } else {
    v
  }
}

///|
/// The four worlds, around real stars from 11 to 20 ly from the Sun that
/// all lie 13.8 to 25.4 ly from each other, inside the 8 to 30 ly a hop
/// may be (`docs/gameplay.md`). Positions are from each star's Wikipedia
/// infobox, read 2026-10-29.
pub let worlds : Array[World] = [
  {
    name: "Kerala",
    star: "τ Ceti",
    ra: hours(1, 44, 4.083),
    dec: degrees(15, 56, 14.93, south=true),
    distance_ly: 11.912,
  },
  {
    name: "Tigray",
    star: "70 Ophiuchi",
    ra: hours(18, 5, 27.285),
    dec: degrees(2, 29, 0.36, south=false),
    distance_ly: 16.68,
  },
  {
    name: "Oaxaca",
    star: "δ Pavonis",
    ra: hours(20, 8, 43.60887),
    dec: degrees(66, 10, 55.4428, south=true),
    distance_ly: 19.89,
  },
  {
    name: "Occitan",
    star: "61 Cygni",
    ra: hours(21, 6, 53.9396),
    dec: degrees(38, 44, 57.902, south=false),
    distance_ly: 11.404,
  },
]

///|
/// Equatorial coordinates in light-years, the Sun at the origin.
pub fn World::position(self : World) -> (Double, Double, Double) {
  let ra = self.ra * 15.0 * @fmath.PI / 180.0
  let dec = self.dec * @fmath.PI / 180.0
  let r = self.distance_ly
  (
    r * @fmath.cos(dec) * @fmath.cos(ra),
    r * @fmath.cos(dec) * @fmath.sin(ra),
    r * @fmath.sin(dec),
  )
}

///|
pub fn World::distance_to(self : World, other : World) -> Double {
  let (x1, y1, z1) = self.position()
  let (x2, y2, z2) = other.position()
  let (dx, dy, dz) = (x1 - x2, y1 - y2, z1 - z2)
  (dx * dx + dy * dy + dz * dz).sqrt()
}

///|
/// The worlds lie within 0.4 ly of one plane, so a map of that plane is
/// true to them. These are its axes, the two largest principal components
/// of the four positions, worked out once offline.
let map_axes : ((Double, Double, Double), (Double, Double, Double)) = (
  (0.090982, 0.326633, -0.940762),
  (0.417355, 0.845209, 0.333820),
)

///|
/// Where the map draws a point, in light-years from the worlds' centroid.
/// The Sun is the point (0, 0, 0).
pub fn on_map(p : (Double, Double, Double)) -> (Double, Double) {
  let mut c = (0.0, 0.0, 0.0)
  for w in worlds {
    let (x, y, z) = w.position()
    c = (c.0 + x, c.1 + y, c.2 + z)
  }
  let n = worlds.length().to_double()
  let d = (p.0 - c.0 / n, p.1 - c.1 / n, p.2 - c.2 / n)
  let (a, b) = map_axes
  (
    d.0 * a.0 + d.1 * a.1 + d.2 * a.2,
    d.0 * b.0 + d.1 * b.1 + d.2 * b.2,
  )
}

///|
pub fn World::on_map(self : World) -> (Double, Double) {
  on_map(self.position())
}

///|
/// The ports of call in order, round again: every pair of worlds, with
/// two flown twice, as no tour of four worlds flies each pair once.
pub let itinerary : Array[World] = [
  worlds[0],
  worlds[3],
  worlds[1],
  worlds[0],
  worlds[2],
  worlds[1],
  worlds[3],
  worlds[2],
]

///|
/// The worlds of the leg after `crossings` dockings: where the ship docked
/// last, or was commissioned, and where it goes next. A leg is named by
/// its place in the itinerary, so reordering the itinerary renames every
/// leg in flight.
pub fn leg(crossings : Int64) -> (World, World) {
  let n = itinerary.length().to_int64()
  let i = (crossings % n).to_int()
  (itinerary[i], itinerary[(i + 1) % n.to_int()])
}

///|
/// The length of that leg, in light-years.
pub fn hop(crossings : Int64) -> Double {
  let (from, to) = leg(crossings)
  from.distance_to(to)
}
