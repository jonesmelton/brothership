///|
/// A settled world, placed where its star is. Worlds are mutually at rest,
/// so time passes alike at all of them, and none keeps a clock the game
/// reads. Worlds are mutually at rest, so their clocks agree.
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
/// The five worlds, around real stars from 11 to 24 ly from the Sun that
/// all lie 13.8 to 29.6 ly from each other, inside the 8 to 30 ly a hop
/// may be (`docs/gameplay.md`). Positions are from each star's Wikipedia
/// infobox, read 2026-10-29 and, for Gliese 667, 2026-10-30. The Three
/// Tyrants is named for its three stars, not a place; its position is
/// Gliese 667 AB's, with the distance of C, which is the better measured.
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
  {
    name: "The Three Tyrants",
    star: "Gliese 667",
    ra: hours(17, 18, 57.16483),
    dec: degrees(34, 59, 23.1416, south=true),
    distance_ly: 23.623,
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
/// The worlds lie within 0.8 ly of one plane, so a map of that plane is
/// true to them within 0.1 ly. These are its axes, the two largest
/// principal components of the five positions, worked out once offline.
let map_axes : ((Double, Double, Double), (Double, Double, Double)) = (
  (0.408526, 0.666525, 0.623579),
  (0.231021, 0.585437, -0.777105),
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
  (d.0 * a.0 + d.1 * a.1 + d.2 * a.2, d.0 * b.0 + d.1 * b.1 + d.2 * b.2)
}

///|
pub fn World::on_map(self : World) -> (Double, Double) {
  on_map(self.position())
}

///|
/// The ports of call ships flew in order before they chose their own, round
/// again: every pair of worlds, with Tigray and Occitan flown three times.
/// Logs from before then name their worlds by it. The first seven legs are those of
/// the four-world itinerary, so legs already in flight keep their worlds.
pub let itinerary : Array[World] = [
  worlds[0],
  worlds[3],
  worlds[1],
  worlds[0],
  worlds[2],
  worlds[1],
  worlds[3],
  worlds[2],
  worlds[4],
  worlds[1],
  worlds[3],
  worlds[4],
]

///|
/// The worlds of the itinerary's leg after `crossings` dockings: where a
/// ship flying it docked last, or was commissioned, and where it went next.
/// Such a leg is named by its place in the itinerary, so reordering the
/// itinerary renames it.
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

///|
/// The world named `name`, if any.
pub fn world_named(name : String) -> World? {
  worlds.iter().find_first(w => w.name == name)
}

///|
/// The world `name` names, or `or` for none: the itinerary's.
fn named_or(name : String?, or : World) -> World {
  name.bind(world_named).unwrap_or(or)
}

///|
/// The world `ship` is in port at, or left from underway.
pub fn origin(ship : @core.Ship) -> World {
  named_or(ship.from, leg(ship.crossings).0)
}

///|
/// The world the ship is bound for. `None` in port until it chooses;
/// underway on a leg of the itinerary, that leg's end.
pub fn bound_for(state : @core.State) -> World? {
  let ship = state.ship
  match state.leg {
    Underway(_) => Some(named_or(ship.bound, leg(ship.crossings).1))
    InPort(_) => ship.bound.bind(world_named)
  }
}

///|
/// The world the ship's last leg left from, if it has flown one.
pub fn came_from(ship : @core.Ship) -> World? {
  guard ship.crossings > 0L else { None }
  Some(named_or(ship.came_from, leg(ship.crossings - 1L).0))
}

///|
/// The longest crossing that counts as short, in light-years. The four
/// shortest hops between the worlds run 13.8 to 15.7 ly and the next is
/// 20.0, so 18 divides neighbours from the rest of the map.
pub const SHORT_CROSSING : Double = 18.0

///|
/// Whether the crossing `ship` has just flown was short, so its next must
/// be a long one: a ship does not make two short crossings running. False
/// before its first crossing.
pub fn flew_short(ship : @core.Ship) -> Bool {
  match came_from(ship) {
    Some(from) => from.distance_to(origin(ship)) < SHORT_CROSSING
    None => false
  }
}

///|
/// The worlds the ship may leave for from port: any but the one it is at
/// and the one it came from, so it never flies straight back, and after a
/// short crossing none short of `SHORT_CROSSING`, so it does not make two
/// short crossings running. A map with no long world open offers them all
/// rather than keeping the ship in port.
pub fn choices(ship : @core.Ship) -> Array[World] {
  let here = origin(ship)
  let back = came_from(ship)
  let open = worlds.filter(w => w != here && Some(w) != back)
  guard flew_short(ship) else { return open }
  let long = open.filter(w => here.distance_to(w) >= SHORT_CROSSING)
  if long.is_empty() {
    open
  } else {
    long
  }
}

///|
/// The worlds a landing's leg ran between.
pub fn landing_leg(l : @core.Landing) -> (World, World) {
  let (from, to) = leg(l.leg)
  (named_or(l.from, from), named_or(l.to, to))
}
