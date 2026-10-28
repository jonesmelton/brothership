// The check-in's three pages, what each page's log holds, and the
// sentences that make accrual and consequence audible: rates beside
// stocks, what a choice changed, and what a player earned while away.

///|
/// A page of the check-in, each with its own log.
pub(all) enum Page {
  /// The player's post, watch, order and craft, and what they earn.
  You
  /// Phase, arrival, drive and demands.
  Voyage
  /// Hull, fit, refits, recruits and the ship's own words.
  Ship
} derive(Debug, Eq, Compare)

///|
/// The page's name as the navigation and headings say it.
pub fn Page::name(self : Page) -> String {
  ignore(self)
  ...
}

///|
/// The page whose log holds `e`. Every happening has exactly one. A line
/// the ship spoke goes with the entry it is about, found in `story`, or to
/// `Ship` when that entry is not there.
pub fn page_of(
  e : @core.Entry,
  you~ : String,
  story~ : Array[@core.Entry],
) -> Page {
  ignore((e, you, story))
  ...
}

///|
/// What a choice changed, at most two sentences, most important first:
/// arrival, then demands that now close differently, then the hull's
/// trend, then `you`'s regard per hour. `before` and `after` are the same
/// instant either side of one proposal. When nothing changed, one sentence
/// saying so and why, such as the coast not needing the drive.
pub fn effect(
  before : @core.State,
  after : @core.State,
  you~ : String,
) -> Array[String] {
  ignore((before, after, you))
  ...
}

///|
/// A player's running totals on one ship, kept by the client between
/// visits so a return can say what was earned. Each never falls, docking
/// included.
pub(all) struct Ledger {
  /// Unix seconds.
  at : Int64
  /// Regard on record plus this crossing's, in `Tally.regard` units.
  regard : Int64
  /// Works delivered plus works finished this crossing.
  works : Int64
  /// Crossings the ship has flown, plus one while underway.
  crossings : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Ledger::of(s : @core.State, you~ : String) -> Ledger {
  ignore((s, you))
  ...
}

///|
/// What `you` earned between two ledgers, for the top of the You page:
/// regard, works, rank reached. Empty when nothing changed.
pub fn since(before : Ledger, now : Ledger) -> Array[String] {
  ignore((before, now))
  ...
}

///|
/// What `you` is earning now, with rates: regard this crossing and per
/// hour, with the ship's ask and an open demand's doubling named; progress
/// toward the next work for an artist; hours of regard to the next rank.
pub fn earning_sentences(s : @core.State, you~ : String) -> Array[String] {
  ignore((s, you))
  ...
}

///|
/// How each open or waiting demand will close if nobody changes post:
/// "Breach will be met with about 40 minutes to spare." or "Breach will be
/// missed by about 2 crew-hours."
pub fn outlook_sentences(c : @core.Crossing) -> Array[String] {
  ignore(c)
  ...
}

///|
/// The ship page: the hull with its trend, each refit's level and effect,
/// the refit under way with its progress and rate, recruits, and works
/// toward the next recruit.
pub fn ship_sentences(s : @core.State) -> Array[String] {
  ignore(s)
  ...
}

///|
/// What `level` of `refit` does, for the ship page and a landed refit:
/// "hull wears 44% less than unfitted".
pub fn refit_effect(refit : @core.Refit, level : Int64) -> String {
  ignore((refit, level))
  ...
}
