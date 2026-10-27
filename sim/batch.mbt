///|
/// What a batch keeps of each run: enough to plot and to reopen the run by
/// its seed.
pub(all) struct Outcome {
  seed : Int64
  arrived_at : Int64
  min_hull : Int64
  end_hull : Int64
  drive_ticks : Int64
  hull_ticks : Int64
  craft_ticks : Int64
  checkins : Int32
  dead_checkins : Int32
  longest_dead : Int64
} derive(Debug, Eq)

///|
pub fn Run::outcome(self : Run) -> Outcome {
  {
    seed: self.seed,
    arrived_at: self.arrived_at,
    min_hull: self.min_hull,
    end_hull: self.end_hull,
    drive_ticks: self.drive_ticks,
    hull_ticks: self.hull_ticks,
    craft_ticks: self.craft_ticks,
    checkins: self.checkins,
    dead_checkins: self.dead_checkins,
    longest_dead: self.longest_dead,
  }
}

///|
pub fn Scenario::batch(
  self : Scenario,
  first_seed~ : Int64 = 1L,
  runs~ : Int32,
) -> Array[Outcome] {
  Array::makei(runs, i => self.run(first_seed + i.to_int64()).outcome())
}

///|
/// The `p`th percentile (0 to 100) by nearest rank. Zero for no values.
pub fn percentile(values : Array[Int64], p : Int32) -> Int64 {
  guard !values.is_empty() else { 0L }
  let sorted = values.copy()
  sorted.sort()
  let rank = (p * sorted.length() + 99) / 100
  sorted[(rank - 1).clamp(min=0, max=sorted.length() - 1)]
}

///|
/// Counts of `values` in `bins` equal bins over `[lo, hi]`. Values outside
/// land in the end bins.
pub fn histogram(
  values : Array[Int64],
  lo~ : Int64,
  hi~ : Int64,
  bins~ : Int32,
) -> Array[Int32] {
  let counts = Array::make(bins, 0)
  let span = (hi - lo).max(1L)
  for v in values {
    let i = ((v - lo) * bins.to_int64() / span).to_int()
    counts[i.clamp(min=0, max=bins - 1)] += 1
  }
  counts
}
