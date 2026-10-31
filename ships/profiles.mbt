///|
/// How a ship chooses what to ask for and what to refit. Stands in for the
/// model, which makes these choices in character in the game.
pub(all) enum Temperament {
  /// Asks for the drive whenever it fires; refits for speed.
  Bold
  /// Asks for the hull when it is worn or breached; refits against wear.
  Careful
  /// Asks for whatever a demand needs, else the emptiest useful post.
  Social
  /// Asks for crafts, and for any demand that pays; refits for repair.
  Sly
} derive(Debug, Eq, Compare, Hash, ToJson, FromJson)

///|
pub fn Temperament::name(self : Temperament) -> String {
  match self {
    Bold => "bold"
    Careful => "careful"
    Social => "social"
    Sly => "sly"
  }
}

///|
/// How a ship is formally identified: `EF-147 顧大嫂 The Tigress`. See
/// `docs/translation.md` and `content/cast/pennants.tsv`.
pub(all) struct Title {
  pennant : String
  /// Traditional Chinese; the source figure's name, not a translation.
  conventional_name : String
  epithet : String
} derive(Debug, Eq)

///|
/// A ship as authored: its kinematics and fittings for a default route,
/// what it values, and its temperament.
pub(all) struct Profile {
  /// The key a ship's log is commissioned under. Never rename a profile
  /// that has flown: replay looks it up by this name.
  name : String
  /// None for the plain ship of the scenarios, which is not in the cast.
  title : Title?
  route : Route
  values : @core.Values
  temperament : Temperament
} derive(Debug, Eq)

///|
pub fn Profile::default() -> Profile {
  {
    name: "a plain ship",
    title: None,
    route: Route::default(),
    values: { drive: 2, hull: 2, craft: 1, },
    temperament: Careful,
  }
}

///|
/// The playtest cast from `content/cast/starting-cast.md`, and the plain
/// ship the scenarios started with.
pub fn profiles() -> Array[Profile] {
  let base = Route::default()
  [
    Profile::default(),
    {
      name: "EF-147 The Tigress",
      title: Some({
        pennant: "EF-147",
        conventional_name: "顧大嫂",
        epithet: "The Tigress",
      }),
      route: {
        ..base,
        accel_g: 38000.0,
        drive_needed: 5,
        wear: 24_000,
        repair: 32_000,
      },
      values: { drive: 1, hull: 3, craft: 2, },
      temperament: Social,
    },
    {
      name: "HS-212 The Twin-Tailed Scorpion",
      title: Some({
        pennant: "HS-212",
        conventional_name: "解寶",
        epithet: "The Twin-Tailed Scorpion",
      }),
      route: {
        ..base,
        accel_g: 46000.0,
        gamma_cap: 26000.0,
        drive_needed: 3,
        wear: 42_000,
        repair: 24_000,
      },
      values: { drive: 3, hull: 1, craft: 1, },
      temperament: Bold,
    },
    {
      name: "EF-287 The Flea on the Drum",
      title: Some({
        pennant: "EF-287",
        conventional_name: "時遷",
        epithet: "The Flea on the Drum",
      }),
      route: {
        ..base,
        accel_g: 42000.0,
        gamma_cap: 20000.0,
        drive_needed: 3,
        wear: 34_000,
        repair: 20_000,
      },
      values: { drive: 1, hull: 1, craft: 3, },
      temperament: Sly,
    },
  ]
}

///|
pub fn Profile::ship(self : Profile, seed~ : Int64) -> @core.Ship {
  @core.Ship::new(self.values, self.route.fit(), seed~)
}

///|
fn Temperament::refit_order(self : Temperament) -> Array[@core.Refit] {
  match self {
    Bold => [Injectors, Coils, Baffles, Plating]
    Careful => [Baffles, Plating, Coils, Injectors]
    Social => [Plating, Baffles, Injectors, Coils]
    Sly => [Coils, Plating, Injectors, Baffles]
  }
}

///|
/// The refit the ship proposes once the last one lands.
pub fn Temperament::refit(
  self : Temperament,
  c : @core.Crossing,
) -> @core.Refit? {
  guard c.fit.refit is None else { c.fit.refit }
  self
  .refit_order()
  .search_by(r => c.fit.can_refit(r))
  .map(i => self.refit_order()[i])
}

///|
/// The post the first open demand needs, if any.
pub fn open_post(c : @core.Crossing) -> @core.Post? {
  c.demands.iter().find_first(d => d.status == Open).map(d => d.hazard.post())
}

///|
/// What the ship asks for now.
pub fn Temperament::ask(self : Temperament, c : @core.Crossing) -> @core.Post? {
  let firing = c.firing()
  match self {
    Bold => if firing { Some(Drive) } else { open_post(c) }
    Careful =>
      if c.hull < @core.HULL_FULL * 6L / 10L ||
        (c.ask == Some(Hull) && c.hull < @core.HULL_FULL * 17L / 20L) ||
        c.demands.iter().any(d => d.status == Open && d.hazard == Breach) {
        Some(Hull)
      } else if firing {
        Some(Drive)
      } else {
        None
      }
    Social =>
      match open_post(c) {
        Some(p) => Some(p)
        None => {
          let useful : Array[@core.Post] = if firing {
            [Drive, Hull]
          } else {
            [Hull, Craft]
          }
          let mut best = useful[0]
          for p in useful {
            if c.count(p) < c.count(best) {
              best = p
            }
          }
          Some(best)
        }
      }
    Sly =>
      match c.demands.iter().find_first(d => d.status == Open) {
        Some(d) if d.hazard.post() == Hull => Some(Hull)
        _ => Some(Craft)
      }
  }
}

///|
/// What the ship does at one instant.
pub(all) enum Act {
  /// Asks for hands on a post, or stops asking. Made only at a moment, and
  /// made even if the ask is unchanged, so the log records when the ship
  /// last reconsidered.
  Ask(@core.Post?)
  /// Builds this refit next. Made only when it differs from the current one.
  Refit(@core.Refit?)
} derive(Debug, Eq)

///|
/// What the ship does now, given the moment at which it last spoke. The
/// ship speaks when something has happened, not whenever the crew move:
/// asking on head counts made recruits, who follow asks, and the ship chase
/// each other from post to post.
///
/// This is where a model call replaces the temperament.
pub fn Temperament::turn(
  self : Temperament,
  c : @core.Crossing,
  spoke : @core.Moment?,
) -> Array[Act] {
  let acts = []
  let refit = self.refit(c)
  if refit != c.fit.refit {
    acts.push(Refit(refit))
  }
  if spoke != Some(c.moment()) {
    acts.push(Ask(self.ask(c)))
  }
  acts
}

///|
/// The stores to load in port for a leg of `distance_ly`: two crew-hours,
/// in quarter-hand-ticks, for each 20 light-years.
pub fn stores_at(distance_ly : Double) -> Int64 {
  let at_20 = 2L * @core.HOUR * @core.HAND
  (at_20.to_double() * distance_ly / 20.0).to_int64()
}

///|
/// The stores `ship` loads in port to leave for `world`. A ship entering
/// service loads `FIRST_STORES` wherever it goes, so officers can sign on
/// before it leaves.
pub fn stores_for(ship : @core.Ship, world : World) -> Int64 {
  guard ship.crossings > 0L else { @core.FIRST_STORES }
  stores_at(origin(ship).distance_to(world))
}

///|
/// What the ship asks for in port, where the drive loads stores and the hull
/// works the yard: leaving sooner, or leaving mended.
pub fn Temperament::port_ask(
  self : Temperament,
  state : @core.State,
) -> @core.Post? {
  match self {
    Bold | Sly => Some(Drive)
    Careful =>
      if state.ship.hull < @core.HULL_FULL {
        Some(Hull)
      } else {
        Some(Drive)
      }
    Social =>
      if state.posted(Hull) <= state.posted(Drive) {
        Some(Hull)
      } else {
        Some(Drive)
      }
  }
}

///|
/// The plan for a leg of `distance_ly`, for a ship with `coils` coasting at
/// `cruise`.
pub fn Profile::next_plan(
  self : Profile,
  distance_ly~ : Double,
  coils~ : Int64,
  cruise~ : Int64 = @core.CRUISE_FULL,
) -> @core.Plan {
  { ..self.route, distance_ly, }.plan_with(coils~, cruise~)
}

///|
/// The world the ship leaves for next from port, among `choices`: a bold
/// ship the farthest, a careful one the nearest, a sly one the second
/// farthest, and a social one any, picked by the ship's seed and crossings.
pub fn Temperament::course(self : Temperament, ship : @core.Ship) -> World {
  let options = choices(ship)
  let here = origin(ship)
  let by_distance = options.copy()
  by_distance.sort_by((a, b) => here.distance_to(a).compare(here.distance_to(b)))
  let n = options.length().to_int64()
  match self {
    Bold => by_distance[by_distance.length() - 1]
    Careful => by_distance[0]
    Sly => by_distance[(by_distance.length() - 2).max(0)]
    Social => {
      let mixed = (ship.seed * 6_364_136_223_846_793_005L +
        ship.crossings * 1_442_695_040_888_963_407L).reinterpret_as_uint64() >>
        33
      options[(mixed % n.reinterpret_as_uint64()).to_int()]
    }
  }
}

///|
/// The ship's choice of `world` as an event, with the stores that leg needs.
pub fn bound(ship : @core.Ship, world : World) -> @core.Event {
  Bound(world=world.name, stores=stores_for(ship, world))
}

///|
/// Docking `state`'s arrived crossing, with stores sized for the world the
/// temperament would choose next. Choosing another resizes them.
pub fn Profile::docked(self : Profile, state : @core.State) -> @core.Event {
  let docked = state.apply(Docked(stores=0)) catch {
    err => abort("ship clock: \{err.to_json().stringify()}")
  }
  let ship = docked.ship
  Docked(stores=stores_for(ship, self.temperament.course(ship)))
}

///|
/// The cruises a ship chooses among, in thousandths of its γ cap.
pub let cruises : Array[Int64] = [1000, 800, 600]

///|
/// The cruise the ship sets in port for a crossing of `distance_ly`.
pub fn Temperament::cruise(
  self : Temperament,
  ship : @core.Ship,
  distance_ly~ : Double,
) -> Int64 {
  ignore(distance_ly)
  match self {
    Bold => 1000
    Careful => if ship.hull < @core.HULL_FULL * 6L / 10L { 600 } else { 800 }
    Social => if ship.hull < @core.HULL_FULL * 8L / 10L { 800 } else { 1000 }
    Sly => 600
  }
}
