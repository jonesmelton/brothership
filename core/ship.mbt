///|
/// Hands are counted in quarters: a crew member is `HAND`, and one standing a
/// watch is `WATCH_HAND`, so a watch is worth a quarter more of the same post.
pub const HAND : Int64 = 4L

///|
pub const WATCH_HAND : Int64 = 5L

///|
pub const HOUR : Int64 = 3600L

///|
/// Work units a lone crafter makes per tick, standing no watch. Work and
/// refit progress are counted in these.
pub const CRAFT_UNIT : Int64 = 16L

///|
/// Work units in one finished work: six crew-hours alone.
pub const WORK_SIZE : Int64 = 345_600L

///|
/// Works delivered, across the crew, for each recruit who joins at port.
pub const WORKS_PER_RECRUIT : Int64 = 3L

///|
/// Most recruits a ship takes on.
pub const MAX_RECRUITS : Int64 = 6L

///|
/// Hull restored by the yard at each port.
pub const PORT_REPAIR : Int64 = 250_000_000L

///|
/// Regard for one tick of one hand at weight 1. Regard is shown in these
/// "hours of plain work".
pub const REGARD_HOUR : Int64 = 14_400L

///|
/// What a crew member's own hours make. See `docs/gameplay.md`.
pub(all) enum Craft {
  /// Ship refits, built together and kept for good.
  Engineer
  /// Works, delivered at port for standing and recruits.
  Artist
} derive(Debug, Eq, Compare, Hash, ToJson, FromJson)

///|
pub(all) enum Refit {
  /// Less wear at every setting.
  Baffles
  /// More repair per hand on the hull.
  Plating
  /// One fewer drive hand for full burn.
  Injectors
  /// A fifth more γ cap, from the next departure: the plan for a route is
  /// fixed when the ship leaves port.
  Coils
} derive(Debug, Eq, Compare, Hash, ToJson, FromJson)

///|
pub let refits : Array[Refit] = [Baffles, Plating, Injectors, Coils]

///|
/// Levels any refit can reach.
pub const MAX_LEVEL : Int64 = 3L

///|
/// What a ship's regard weighs, per hand on each post. Authored per ship
/// from its faces; a weight of zero means the ship does not notice the post.
pub(all) struct Values {
  drive : Int64
  hull : Int64
  craft : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Values::weight(self : Values, post : Post) -> Int64 {
  match post {
    Drive => self.drive
    Hull => self.hull
    Craft => self.craft
  }
}

///|
/// A ship's fittings: the rates its crew work against, and the refit its
/// engineers are building. Carried from crossing to crossing.
pub(all) struct Fit {
  /// Drive hands for full burn.
  needed : Int64
  /// Hull lost per tick at full burn. Scales with the setting squared.
  wear : Int64
  /// Hull restored per tick by each hand on the hull.
  repair : Int64
  baffles : Int64
  plating : Int64
  injectors : Int64
  coils : Int64
  /// What the engineers are building, if anything.
  refit : Refit?
  /// Work units put into the next refit. Kept when the refit changes.
  progress : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Fit::new(needed~ : Int64, wear~ : Int64, repair~ : Int64) -> Fit {
  {
    needed,
    wear,
    repair,
    baffles: 0,
    plating: 0,
    injectors: 0,
    coils: 0,
    refit: None,
    progress: 0,
  }
}

///|
pub fn Fit::level(self : Fit, refit : Refit) -> Int64 {
  match refit {
    Baffles => self.baffles
    Plating => self.plating
    Injectors => self.injectors
    Coils => self.coils
  }
}

///|
/// Whether `refit` can be built again. Injectors stop at two drive hands.
pub fn Fit::can_refit(self : Fit, refit : Refit) -> Bool {
  self.level(refit) < MAX_LEVEL && (refit != Injectors || self.needed > 2L)
}

///|
/// Work units for the next level of `refit`: half again for each level
/// already built.
pub fn Fit::cost(self : Fit, refit : Refit) -> Int64 {
  let hours = match refit {
    Baffles => 5L
    Plating => 4L
    Injectors => 6L
    Coils => 10L
  }
  let base = hours * HOUR * CRAFT_UNIT
  for i = 0L, c = base {
    if i >= self.level(refit) {
      break c
    }
    continue i + 1L, c * 3L / 2L
  }
}

///|
/// The fit with one more level of `refit`, its cost paid from progress.
fn Fit::build(self : Fit, refit : Refit) -> Fit {
  let progress = self.progress - self.cost(refit)
  let next = match refit {
    Baffles =>
      { ..self, baffles: self.baffles + 1L, wear: self.wear * 3L / 4L, }
    Plating =>
      { ..self, plating: self.plating + 1L, repair: self.repair * 5L / 4L, }
    Injectors =>
      { ..self, injectors: self.injectors + 1L, needed: self.needed - 1L, }
    Coils => { ..self, coils: self.coils + 1L, }
  }
  let refit = if next.can_refit(refit) { Some(refit) } else { None }
  { ..next, progress, refit, }
}

///|
/// What the ship remembers of one crew member across crossings.
pub(all) struct Record {
  regard : Int64
  /// Works delivered.
  works : Int64
  /// Work units toward the next work, carried to the next crossing.
  carry : Int64
  /// Rank held. Missing in a record written before promotions: the rank
  /// falls back to `rank_floor(regard)` until the next dock writes it.
  rank : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Ensign, the first rank.
pub const ENSIGN : Int64 = 0L

///|
/// Lieutenant junior grade.
pub const LIEUTENANT_JUNIOR : Int64 = 1L

///|
pub const LIEUTENANT : Int64 = 2L

///|
pub const LIEUTENANT_COMMANDER : Int64 = 3L

///|
/// Commander, the highest rank.
pub const COMMANDER : Int64 = 4L

///|
/// Regard, in `REGARD_HOUR`s, at which each rank becomes available.
pub let rank_thresholds : Array[Int64] = [0, 40, 120, 280, 500]

///|
/// The highest rank a regard makes someone eligible for: 0 to 4. A rank held
/// is a record's `rank`, not this.
pub fn rank_floor(regard : Int64) -> Int64 {
  let hours = regard / REGARD_HOUR
  let mut rank = ENSIGN
  for i, at in rank_thresholds {
    if hours >= at {
      rank = i.to_int64()
    }
  }
  rank
}

///|
/// The ship between crossings: what it is fitted with, the state of its
/// hull, who it remembers, and how many recruits crew it.
pub(all) struct Ship {
  values : Values
  fit : Fit
  hull : Int64
  records : Map[String, Record]
  recruits : Int64
  /// Works delivered toward the next recruit.
  toward_recruit : Int64
  /// Crossings flown. With `seed`, picks each crossing's demands.
  crossings : Int64
  seed : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Ship::new(values : Values, fit : Fit, seed~ : Int64) -> Ship {
  {
    values,
    fit,
    hull: HULL_FULL,
    records: {},
    recruits: 0,
    toward_recruit: 0,
    crossings: 0,
    seed,
  }
}

///|
/// `crew`'s rank: the record's explicit rank, else the floor for its regard,
/// else 0.
pub fn Ship::rank(self : Ship, crew : String) -> Int64 {
  match self.records.get(crew) {
    Some({ rank: Some(r), .. }) => r
    Some(r) => rank_floor(r.regard)
    None => ENSIGN
  }
}
