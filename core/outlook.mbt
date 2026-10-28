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
  guard self.phase != Arrived else {
    { span: @math.TICKS_PER_HOUR, regard: 0, work: 0, hull: 0, refit: 0, }
  }
  let span = self.next_boundary().min(@math.TICKS_PER_HOUR).max(1L)
  // `flow` rather than `apply`: the boundary's own settling (a watch's
  // bonus, a missed demand's loss, a salvage) is a jump, not a rate.
  let after = self.flow(span)
  let before_tally = self.tallies.get(crew).unwrap_or(no_tally)
  let after_tally = after.tallies.get(crew).unwrap_or(no_tally)
  {
    span,
    regard: @math.per_hour(after_tally.regard - before_tally.regard, span),
    work: @math.per_hour(after_tally.work - before_tally.work, span),
    hull: @math.per_hour(after.hull - self.hull, span),
    refit: @math.per_hour(after.fit.progress - self.fit.progress, span),
  }
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
  let out : Array[Outcome?] = self.demands.map(d => closed_outcome(self.t, d))
  let mut c = self
  for _ in 0..<MAX_BOUNDARIES {
    if c.arrived_at is Some(_) {
      return Some(out.map(o => o.unwrap()))
    }
    let step = c.next_boundary()
    let next = c.advance(step)
    for i, d in next.demands {
      if out[i] is None && (d.status == Met || d.status == Missed) {
        // Closing happens somewhere in `(c.t, c.t + step]`: find the first tick.
        let mut lo = 1L
        let mut hi = step
        while lo < hi {
          let mid = lo + (hi - lo) / 2L
          if c.advance(mid).demands[i].status is (Met | Missed) {
            hi = mid
          } else {
            lo = mid + 1L
          }
        }
        out[i] = closed_outcome(c.t + lo, c.advance(lo).demands[i])
      }
    }
    c = next
  }
  None
}

///|
/// `d` as it stands at tick `at`, if closed.
fn closed_outcome(at : Int64, d : Demand) -> Outcome? {
  match d.status {
    Met => Some({ status: Met, at, short: 0, })
    Missed => Some({ status: Missed, at, short: (d.need - d.done).max(0L), })
    Waiting | Open => None
  }
}
