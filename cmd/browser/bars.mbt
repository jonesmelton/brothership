// Progress bars: a picture of a sentence beside it, never more than it.
// Hidden from assistive technology. See docs/visual-design.md.

///|
/// How full a bar is, in thousandths, clamped to 0 through 1000.
fn fill_of(done : Int64, of : Int64) -> Int64 {
  if of <= 0L || done <= 0L {
    0L
  } else {
    (done * 1000L / of).min(1000L)
  }
}

///|
/// A groove with `done` of `of` filled.
fn bar(done : Int64, of : Int64) -> @rabbita.Html {
  let p = fill_of(done, of)
  @html.div(class="bar", [
    @html.div(class="fill", style=["width: \{p / 10L}.\{p % 10L}%"], ""),
  ])
}

///|
/// A bar with a label above it. The sentence it repeats is beside it.
fn measure(label : String, done : Int64, of : Int64) -> @rabbita.Html {
  @html.div(class="measure", attrs=@html.Attrs::build().aria_hidden("true"), [
    @html.span(class="label", label),
    bar(done, of),
  ])
}

///|
/// `crew`'s work toward the next work, as done and size, for an artist.
fn work_span(c : @core.Crossing, crew : String) -> (Int64, Int64)? {
  guard c.hands.get(crew) is Some(h) && h.craft == Artist else { None }
  let carry = c.ship.records.get(crew).map(r => r.carry).unwrap_or(0L)
  let work = c.tallies.get(crew).map(t => t.work).unwrap_or(0L)
  Some(((carry + work) % @core.WORK_SIZE, @core.WORK_SIZE))
}

///|
/// `crew`'s regard since their held rank's threshold and what the next
/// rank's threshold asks, or `None` at the highest rank or when not aboard.
/// Regard past the next threshold fills the bar.
fn regard_span(c : @core.Crossing, crew : String) -> (Int64, Int64)? {
  guard c.hands.get(crew) is Some(h) else { None }
  let rank = h.rank.max(0L).to_int()
  guard rank + 1 < @core.rank_thresholds.length() else { None }
  let kept = c.ship.records.get(crew).map(r => r.regard).unwrap_or(0L)
  let made = c.tallies.get(crew).map(t => t.regard).unwrap_or(0L)
  let from = @core.rank_thresholds[rank] * @core.REGARD_HOUR
  let to = @core.rank_thresholds[rank + 1] * @core.REGARD_HOUR
  Some(((kept + made - from).min(to - from), to - from))
}

///|
/// The refit under way and what it costs, or `None` when none is.
fn refit_span(c : @core.Crossing) -> (@core.Refit, Int64, Int64)? {
  c.fit.refit.map(r => (r, c.fit.progress, c.fit.cost(r)))
}
