// Where a crossing is heading if nobody changes anything: the rates a
// player sees beside each stock, and how each demand will close. Derived
// from the state by advancing a copy; nothing here is written to the log.

///|
/// How the crossing is moving now, per hour, until the next boundary. A
/// rate holds only until then, so `span` says for how long.
pub(all) struct Trend {
  /// Ticks the rates hold for: until the next boundary, at most an hour.
  span : Int64
  /// `crew`'s regard per hour, in the units of `Tally.regard`.
  regard : Int64
  /// `crew`'s work units per hour, in the units of `Tally.work`.
  work : Int64
  /// The hull per hour, in the units of `HULL_FULL`; negative while it wears.
  hull : Int64
  /// The refit under way: work units per hour, in the units of `Fit.progress`.
  refit : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// The trend for `crew`, who need not be aboard (then their rates are 0).
/// Rates are `@math.per_hour` of the change over `span`.
pub fn Crossing::trend(self : Crossing, crew : String) -> Trend {
  ignore((self, crew))
  ...
}

///|
/// How one demand closes if nobody changes post.
pub(all) struct Outcome {
  /// `Met` or `Missed`.
  status : Status
  /// Ticks since departure at which it closes.
  at : Int64
  /// Quarter-hand-ticks still needed when it closes; 0 when met.
  short : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// For each of `self.demands`, in order, how it closes if nobody changes
/// post: the closed status of one already closed, or the first instant a
/// waiting or open demand closes. `None` for all when `project` fails.
pub fn Crossing::outcomes(self : Crossing) -> Array[Outcome]? {
  ignore(self)
  ...
}
