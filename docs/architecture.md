# architecture

## packages

| Package       | Targets   | Role                                                                  |
| ------------- | --------- | --------------------------------------------------------------------- |
| `core/math`   | js native | Verified arithmetic kernels (`moon prove`). Proof-friendly code only. |
| `core`        | js native | Events, state, the transition function, wire types, optimistic sync.  |
| `ships`       | js native | Routes and their float plans, ship profiles, itinerary, the ship's scripted turn. |
| `sim`         | js native | The crossing simulator: scenarios, crew policies, batches, voyages.   |
| `store`       | native    | sqlite event log; replays through `core` on open.                     |
| `api`         | native    | Moonback routes over `store`.                                         |
| `cmd/server`  | native    | Server entry: opens the store, serves the API and static assets.      |
| `cmd/browser` | js        | Rabbita (TEA) client.                                                 |
| `llm`         | js native | Model calls: `Call`, `Backend` and its wrappers (route, limit, retry). |
| `llm/prompt`  | js native | Minijinja templates, strict undefined, set up for markdown.           |
| `llm/cache`   | native    | Content-addressed reply cache, one json file per call.                |
| `llm/gate`    | js native | Classifies model text against a policy (`content/gate/policy.md`).    |
| `cast`        | native    | The cast pipeline: entry, portrait, faces. See `docs/cast.md`.        |
| `cmd/cast`    | native    | Cast pipeline CLI over `content/cast`.                                |
| `cmd/gate`    | native    | Checks messages, or `content/gate/samples`, against the gate policy.  |
| `cmd/survey`  | native    | Prints the crossing simulator's batches, comparisons and voyages.     |
| `cmd/harness` | js        | The simulator in a browser page (`make sim`).                         |

Stack: rabbita (frontend), warren (build and dev server), moonback on
moonbitlang/async (server), moonbit-community/sqlite3 (vendored sqlite,
async API), moonbitlang/quickcheck (property tests), gaato/openai and
bobzhang/minijinja (model calls and prompt templates; see `docs/llm-tooling.md`).

## sync

The client and server run the same `core`. `State::apply` is the only
transition: the server uses it to validate and commit, the client to predict.

The client applies its proposals locally for immediate feedback and sends them
one at a time. Each receipt, accepted or refused, carries the server's
snapshot, which the client adopts as confirmed state. Sending one at a time is
what makes this sound: each receipt's snapshot contains exactly the client's
earlier proposals. `Optimistic::resync` ignores snapshots while a proposal is
in flight for the same reason.

On a transport error the client drops its pending proposals and reloads the
snapshot, so queued input is lost. Fixing that needs idempotent proposals on
the server.

Only the server moves game time. Clients propose an `Intent`; the log holds
`Event`, which adds the server's `Tick(at)` in Unix seconds, `Departed`,
`Docked`, and the ship's `Asked` and `Refitting`. Before anything it writes,
the store appends a tick at the wall clock, so a receipt's snapshot may
include a tick and the ship's response to the proposal as well as the
proposal itself; `seq` counts them all. Between receipts the client applies
a local `Tick(at=now)` to its prediction for display and never proposes one.
It also polls the snapshot, since the ship acts on its own.

`cmd/server` runs one clock per ship in `@ships.fleet()`. Each sleeps
until its berth's next advance (`Berth::next_advance`), then calls
`Store::advance` for that ship. A berth has a `lag`, its own second in the
minute: it advances at that second when idle, and that long after each of
the ship's instants (`Profile::wake`: a rate boundary, arrival, or the end
of the port stay). Ships with the same instant, such as ships departing
together, therefore take their turns, and will call a model, at different
seconds. What a ship does at an instant is the pure function `Profile::due`
in `ships`, tested without sleeping.

## model latency

Model text reaches a player seconds after whatever prompted it, and
everything that shows model text has to be built around that wait. Every
message passes at least two model calls in sequence before a player sees
it: the ship writes it, then the gate (`llm/gate`) checks it.

Measured 2026-10-27 on Meta Model API, one run of 18 gate checks of about
930 input and 680 output tokens each:

| model | median | range |
| --- | --- | --- |
| `muse-spark-1.3` | 2.1 s | 1.3 to 4.8 s |
| `muse-spark-1.3-contributor` | 5 s | 2.6 to 23.5 s |

Generation has not been measured. It writes more than a check does, so
expect it to take longer.

- A model call never sits between a player's input and its feedback. The
  input is applied and committed at once; the message arrives later as its
  own event in the log.
- The interface shows that a message is pending, and announces it when it
  lands with the priority of its event (`docs/accessibility.md`), not the
  priority of the input that prompted it.
- A call that fails or is blocked leaves no message. The event that
  prompted it still stands, and the scripted policy covers any choice the
  model would have made.
- The harness and tests never wait on a model: they use the scripted
  policies.

## api

- `GET /healthz` returns `{"ok": true}`. It is the path `fly.toml` checks.
  The listener binds only after the store opens, so a response proves boot got
  that far; keep it independent of the game routes.
- `GET /api/ships` returns `Array[@core.Listing]`, in order of commission.
- `GET /api/ships/:id/snapshot` returns `@core.Snapshot`.
- `POST /api/ships/:id/proposals` takes `@core.Proposal` and returns
  `@core.Receipt`. An unknown ship is a 404.
  A proposal is a crew id and an `Intent`. Nothing checks the id: until
  there are accounts, any client can act as any crew member. A body naming
  a server event fails to decode and gets a 400.

## store

Every accepted event is a row in `event` with the ship's id and a json
body: crew intents, ticks, departures and dockings, and the ship's asks and
refits. Each ship's log begins with `Commissioned`, which carries the ship
and the name of the profile it flies by, so replay needs nothing outside
the log. The server commissions every berth in `@ships.fleet()` that isn't
in service yet when it starts. A tick is written for each ship at least once
a minute while the server runs. The events one call appends go in one
transaction. A snapshot's `seq` is the log position of the ship's latest
row, so it rises but skips. Each ship's in-memory snapshot is its rows
replayed through `State::apply` and is rebuilt on open. Logs from before
commissioning are kept in `event_legacy` and not replayed.
Migrations live in `store/schema.mbt`, are forward-only and are tracked with
`pragma user_version`; append new ones, never edit a shipped one. Writes are
serialized by a mutex so validation sees the state the event will follow.

## verification

- Snapshot tests: `inspect`, `debug_inspect`, `json_inspect`; `moon test -u`
  fills them in.
- Property tests: `@qc.quick_check_fn` in `core/sync_test.mbt`.
- Proofs: `moon prove` checks every `proof_enabled` package. Why3 ships with
  the toolchain; it needs an SMT solver on `PATH`.

`moon prove` lowers every file in a proof-enabled package to WhyML and rejects
`Array`, top-level `let` (use `const`), and `raise` inside contracted
functions. Functions without contracts are not verified, including their call
sites. Keep proofs in `core/math` and have `core` wrap them with total,
contracted functions such as `try_advance`.

## cross-target determinism

`core` runs on js and native and both must compute identical results. Every
number in `core` is `Int64`, fixed-point where a fraction is needed. `Int64`
is emulated on js, so it is slower there but exact. Don't use floats in
`core`: JS `Math` and native libm can differ in the last bits, and clang may
fuse `a*b+c` into an FMA where JS won't. Floats belong in rendering only.

`Int64` serializes to JSON as a decimal string (`"clock": "9"`), because JS
numbers lose precision above 2^53.
