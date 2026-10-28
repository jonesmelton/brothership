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
/// A ship as authored: its kinematics and fittings for a default route,
/// what it values, and its temperament.
pub(all) struct Profile {
  name : String
  route : Route
  values : @core.Values
  temperament : Temperament
} derive(Debug, Eq)

///|
pub fn Profile::default() -> Profile {
  {
    name: "a plain ship",
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
        Some(d) if d.hazard == Salvage => Some(Craft)
        Some(d) if d.hazard == Breach => Some(Hull)
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
/// The hops the ship flies, in light-years, one after another and round
/// again. All are 8 to 30 ly: see `docs/sim.md` for the floor.
pub let itinerary : Array[Double] = [12.0, 20.0, 8.0, 26.0, 15.0, 30.0]

///|
/// How long the ship stays in port between crossings, in seconds.
pub const PORT_STAY : Int64 = 600L

///|
/// The plan for the hop after `legs` crossings, for a ship with `coils`.
pub fn Profile::next_plan(
  self : Profile,
  legs~ : Int64,
  coils~ : Int64,
) -> @core.Plan {
  let n = itinerary.length().to_int64()
  let distance_ly = itinerary[(legs % n).to_int()]
  { ..self.route, distance_ly, }.plan_with(coils~)
}
