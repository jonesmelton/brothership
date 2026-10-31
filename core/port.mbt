// The launch: in port the ship waits on its stores, which hands on the
// drive load, while hands on the hull work the yard. Port dockhands work
// both at a floor rate, so every launch finishes.

///|
/// Stores the port's dockhands load per tick, whoever is aboard: one hand's
/// quarters.
pub const DOCKHANDS : Int64 = 4L

///|
/// Hull the yard restores per tick with nobody on the hull: about a quarter
/// hull over two hours.
pub const YARD_FLOOR : Int64 = 35_000L

///|
/// Stores a newly commissioned ship loads before its first departure: ten
/// minutes of the dockhands' work, so officers can sign on before it leaves.
pub const FIRST_STORES : Int64 = 2400L

///|
/// The ship in port.
pub(all) struct Port {
  /// Docked at, in Unix seconds.
  since : Int64
  /// Left to load before the ship can depart, in quarter-hand-ticks.
  stores : Int64
  /// The stores the next leg needs in all, loaded or not: set at docking,
  /// and again when the ship chooses its next world.
  needed : Int64
  /// The post the ship is asking for, if any.
  ask : Post?
  /// Whether the ship has reconsidered its ask this port stay. It does once,
  /// at docking: crew moving is not a moment.
  spoke : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Port::new(since : Int64, stores : Int64) -> Port {
  { since, stores, needed: stores, ask: None, spoke: false, }
}

///|
/// The port with the next leg needing `needed` stores in all. What is
/// loaded already counts toward them.
fn Port::resize(self : Port, needed : Int64) -> Port {
  let stores = (self.stores + needed - self.needed).max(0L)
  { ..self, stores, needed, }
}

///|
/// Where the launch is heading if no one changes post.
pub(all) struct Launch {
  /// Stores loaded per tick.
  load : Int64
  /// Hull the yard restores per tick.
  mend : Int64
  /// When the stores are loaded and the ship may depart, in Unix seconds.
  ready_at : Int64
  /// The hull then.
  hull : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Officers who name `post` for departure. In port they work it.
pub fn State::posted(self : State, post : Post) -> Int64 {
  self.officers.values().filter(o => o.post == Some(post)).count().to_int64()
}

///|
/// Per-tick rates in port: stores loaded, and hull restored. Craft does
/// nothing in port.
fn State::port_rates(self : State) -> (Int64, Int64) {
  (
    DOCKHANDS + HAND * self.posted(Drive),
    YARD_FLOOR + self.ship.fit.repair * self.posted(Hull),
  )
}

///|
/// The launch as it stands, or `None` underway.
pub fn State::launch(self : State) -> Launch? {
  guard self.leg is InPort(port~) else { None }
  let (load, mend) = self.port_rates()
  let ticks = @math.ticks_to_empty(port.stores, load)
  let hull = @math.settle(self.ship.hull, mend, ticks, HULL_FULL)
  Some({ load, mend, ready_at: self.at + ticks, hull, })
}

///|
/// `self` in `port` ticked to `at`. Both stocks are linear: their rates
/// change only when an officer's post does, which is never inside a tick.
fn State::load(self : State, port : Port, at : Int64) -> State {
  let (load, mend) = self.port_rates()
  let mut stores = port.stores
  let mut hull = self.ship.hull
  let mut left = at - self.at
  while left > 0L {
    let step = left.min(@math.MAX_TICKS)
    stores = @math.deplete(stores, load, step)
    hull = @math.settle(hull, mend, step, HULL_FULL)
    left -= step
  }
  {
    ..self,
    at,
    ship: { ..self.ship, hull, },
    leg: InPort(port={ ..port, stores, }),
  }
}
