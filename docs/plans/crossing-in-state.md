# plan: the crossing in state, store and API

Make the crossing the game's state. Today `@core.State` is a bare clock, and
`@core.Crossing` (posts, watches, standing orders, demands, refits, docking)
lives only in the simulator. When this plan is done, the server's sqlite log
holds a voyage, players change post and stand watches through the API, the
server alone moves time forward, and a scripted ship asks and refits on a
timer. A minimal browser screen shows the check-in.

Read these first: `AGENTS.md`, `docs/architecture.md` (all of it: this
changes `core`, the sync protocol's events and the store's contents),
`docs/gameplay.md` (the check-in, watches, standing orders, demands, port),
`docs/decisions.md`, and `docs/sim.md`. The rules themselves are done and
tested in `core/crossing.mbt`, `core/ship.mbt` and `core/demand.mbt`; this
plan wires them up and should not change them except where a step says so.

## facts established before writing this

Checked on 2026-10-27 against the repo at `605b3b5`.

- `core/state.mbt` has `Event::Elapsed(ticks~)` and `State { clock }`.
  `Store::propose` in `store/store.mbt` applies the proposed event with
  `State::apply`, inserts its JSON into `event`, and keeps the snapshot in
  memory. `load` replays every row on open.
- Clients propose `Elapsed` themselves: `cmd/browser/main.mbt` has an
  "Elapse one tick" button, and `store/store_test.mbt` and
  `api/routes_test.mbt` propose `Elapsed`. A client can therefore move game
  time, which the idle-core research (`research/idle-core.md`, "Accept
  intents, never quantities") rules out.
- `Crossing`, `Ship`, `Hand`, `Tally`, `Fit`, `Record` and `Demand` derive
  `Debug` and `Eq`; most of the leaf types also derive `ToJson` and
  `FromJson`, but `Crossing` and `Ship` do not.
- Crew are `Int32` keys of `Map`s (`Crossing.hands`, `Crossing.tallies`,
  `Ship.records`). Core's `ToJson` covers `Map[K, V]` for any `K : Show`, but
  `FromJson` exists only for `Map[String, V]`
  (`~/.moon/lib/core/json/from_json.mbt`). A snapshot with crew in it cannot
  be decoded as things stand.
- `Int64` encodes as a decimal string (`"clock": "9"`); keep that.
- `Route::plan` (`sim/route.mbt`) is the only floating-point step between a
  route and the game. Ship profiles and the ship's scripted choices
  (`Temperament::ask`, `Temperament::refit`) are in `sim/ships.mbt`. The
  rule that the ship reconsiders its ask only at a "moment" (phase, demand
  statuses, band) is inline in `Scenario::fly` in `sim/run.mbt`.
- `moonbitlang/async` has `sleep(ms : Int)`. `Store` serializes writes with
  `@async.Mutex`.

## decisions this plan makes

State them in the PR. Propose a `docs/decisions.md` entry for the first two.

- **Time is a server event.** A new server-only event `Tick(at~ : Int64)`
  carries Unix seconds. `State` stores the `at` of the last tick; applying a
  later tick advances the crossing by the difference, and an earlier or
  equal one changes nothing. One tick is one second, so there is no
  remainder to carry, and a backward wall clock costs nothing. Replay never
  reads the clock.
- **Clients send intents, the server writes events.** Split the type: a
  client `Proposal` carries an `Intent` (post, leave, craft, watch, order,
  refit choice). The log holds `Event`, which is an intent with its crew, or
  a server event: `Tick`, `Departed(plan)`, `Docked`, and the ship's
  `Asked` and `Refitting`. A client cannot name a server event, because the
  type has no constructor for it.
- **Crew ids are strings.** Change `Int32` crew ids to `String` throughout
  core and sim. This fixes decoding and is what player identity will be
  anyway. Until there is auth, the browser makes an id once, keeps it in
  `localStorage`, and sends it with each proposal. Say in the PR that any
  client can act as any crew member.
- **Plans are computed by the server and stored in the log.** `Departed`
  carries the integer `@core.Plan`. Nothing replays `Route::plan`, so the
  float step happens once, on the server, and replay is exact on both
  targets (see "a crossing is linear stocks per phase" in decisions).

## steps

Commit after each numbered step, with `make check` passing. Steps 1 to 4 can
land without the browser changing behaviour beyond the removed button.

1. **String crew ids, and JSON for the whole crossing.** Change every crew
   id from `Int32` to `String` in `core` and `sim` (`Crossing`, `Ship`,
   events, `Scenario::fly`, recruits as `"recruit 1"` and so on,
   `cmd/survey`, `cmd/harness`). Derive `ToJson` and `FromJson` on
   `Crossing`, `Ship` and anything they hold. Add a property test in
   `core/crossing_test.mbt`: for any schedule from `drive_schedule`, decoding
   `c.to_json()` gives a crossing equal to `c`, and its `forecast` is equal.
   Expected result: every existing law still passes unchanged in meaning, and
   `cmd/survey` prints the same numbers as before for the same seeds.

2. **A shared package for routes, ship profiles and the ship's policy.** Move
   `Route`, `Profile`, `profiles()`, `Temperament` and its `ask` and `refit`
   out of `sim` into a new package `ships` (`js` and `native`; it needs
   `moonbitlang/core/math` for the floats). Move the "moment" rule out of
   `Scenario::fly` into `ships` as a function both the simulator and the
   server call, so they cannot drift. Add a fixed itinerary to `ships`: a
   list of distances in light-years, all between 8 and 30 (`docs/sim.md`
   explains the 8 ly floor). `sim` imports `ships`. Add the package to the
   table in `docs/architecture.md`, and while there add the rows for `sim`
   and `cmd/harness`, which are missing. Expected result: `sim` tests and
   `cmd/survey` output unchanged.

3. **`State` holds the voyage.** In `core/state.mbt`:

   ```moonbit
   pub(all) struct State {
     at : Int64            // Unix seconds of the last Tick; 0 before the first
     ship : Ship
     leg : Leg
   }

   pub(all) enum Leg {
     InPort(since~ : Int64, legs~ : Int64)   // legs flown so far
     Underway(crossing~ : Crossing)
   }
   ```

   `State::initial` needs a `Ship`; take the profile and seed as arguments
   rather than choosing them in core. Define `Intent` (the crew-sent subset:
   `Posted`, `Left`, `Crafted`, `Watched`, `Ordered`, `Refitting`) and
   `Event` (`Crew(crew~, intent~)` plus `Tick`, `Departed(plan~)`, `Docked`,
   `Asked(post~)`, and a ship `Refitting` that is distinct from the crew's).
   `State::apply` forwards crew and ship events to `Crossing::apply` when
   underway, turns `Tick` into `Elapsed` on the crossing, makes `Departed` a
   `Crossing::new` with the state's ship, and makes `Docked` call
   `Crossing::dock`. Refuse with a named `Rejected` case: crew events in
   port, `Departed` while underway, `Docked` before arrival. Keep
   `Rejected` small and give each case the rejected input. Remove
   `Event::Elapsed` and its `NonPositiveTicks` and `ClockOverflow` rejections
   if nothing else uses them; `@math.try_advance` stays proved either way.
   Port the laws: splittability over `Tick`s, the envelope law, and the
   forecast law, each driving `State` instead of `Crossing`. Expected result:
   `core/state_test.mbt` and `core/sync_test.mbt` pass with `Tick` in place
   of `Elapsed`, including the `Optimistic` property tests.

4. **The server owns time.** `Store::propose` takes the wall clock as an
   argument (`now~ : Int64`, Unix seconds) so tests can pass any time. Under
   the write mutex it first appends `Tick(at=now)` if `now` is after
   `state.at`, then validates and appends the proposal's event. Both rows go
   in one sqlite transaction, or neither does. The receipt's snapshot
   includes both, and `seq` counts both rows, so the client's
   one-proposal-at-a-time rule in `core/sync.mbt` still holds. Add
   `Store::advance(now~)` for the ship clock in step 5: it appends the tick
   and whatever the ship does at that instant (step 5), in one transaction.
   `api/routes.mbt` passes the real clock. Update `store_test.mbt` and
   `routes_test.mbt` to propose intents and pass `now`. New tests:
   - a proposal with `now` earlier than `state.at` appends no tick;
   - a store reopened from its file has a snapshot equal to the live one
     after a full crossing of proposals and ticks (this is the replay law
     for the store);
   - the JSON body of a client proposal naming `Tick` is refused with 400,
     because `Intent` cannot decode it.

   Expected result: the browser's "Elapse one tick" button no longer
   compiles; replace it with the step 6 screen or a plain snapshot view.

5. **The ship clock.** In `cmd/server`, start one background task beside the
   HTTP server. It loops: read the snapshot, work out the next instant
   something happens, sleep until then or for 60 s, whichever is sooner,
   then call `Store::advance(now)`. "Something happens" is the crossing's
   next boundary (`state.at + crossing.next_boundary()`), arrival, or the
   end of the port stay. `Store::advance` then, in order:
   1. appends `Tick(at=now)`;
   2. if the crossing has arrived, appends `Docked`;
   3. if in port and the stay is over, appends `Departed` with the plan for
      the next itinerary leg, computed by `ships` with the ship's coils;
   4. if underway and the moment changed since the ship last spoke, appends
      the ship's `Asked` from `Temperament::ask`, and its `Refitting` from
      `Temperament::refit` if the refit changed.

   Run step 4 after every accepted proposal too, since a crew change can
   open a moment (a demand met). The port stay is a constant in `ships`;
   start at 10 minutes, so the first session happens in port as
   `docs/gameplay.md` asks. The model replaces `Temperament` later, under
   "model latency" in `docs/architecture.md`; leave a single function where
   that call will go and do not call a model in this plan. Test the clock
   logic as a pure function of a snapshot and `now`, in `store` or `ships`,
   without sleeping. Expected result: a server left running with no clients
   flies the itinerary, docking and departing, and its log replays to the
   same snapshot.

6. **A check-in screen.** Replace `cmd/browser`'s view with the check-in in
   `docs/gameplay.md`: where the ship is (phase, hull, setting, forecast
   arrival in words), what changed since the player's last visit, and the
   five choices. Render from `predicted()` with a local `Tick(at=now)`
   applied, so the clock and forecast move between receipts; never propose
   a tick. Follow `docs/accessibility.md` from the start: every fact is a
   sentence first, choices are native controls in a predictable order, the
   forecast is in words that coarsen with distance and do not tick
   (`research/liveship-travel-math.md` section 11), and nothing needs to be
   done within a time window. Use the typography in `docs/typography.md`.
   Keep it small: one screen, no routing.

## after the steps

Update `docs/architecture.md`: the api section (proposals carry intents and
a crew id), the sync section (the server appends ticks; clients extrapolate),
and the store section (tick and ship rows). Change the sentence in
`docs/gameplay.md` "rules core" that says a scheduler fires phase changes:
phase changes need no scheduler, because any event steps through them, and
the scheduler exists so the ship can speak at the right instant.

## out of scope

- Auth and accounts. String ids are the seam for them.
- Model calls for asks, refits or speech. `Temperament` stands in.
- Choosing destinations at port, charts and navigators, standing at worlds.
- More than one ship. One `State` is one ship's voyage.
- Pipelined proposals (see the sync decision).

## done when

- `make check` passes.
- No client-sendable type can express `Tick`, `Departed`, `Docked`, or a ship
  event.
- A store reopened from disk equals the live store after a full crossing.
- `cmd/survey` prints the numbers it printed before step 1 for the same
  seeds, or the PR explains each difference.
- Started with `make dev` and left alone, the server departs, flies, docks
  and departs again, and the browser shows the crossing moving without a
  reload.
