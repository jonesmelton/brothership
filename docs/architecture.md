# architecture

## the three claims

1. **One transition function, shared by client and server.** `core` owns
   `State::apply`; the client predicts with it and the server validates and
   commits with it. A proposal is applied locally at once and sent on its
   own, and each receipt carries the authoritative snapshot, so predicted
   and confirmed state cannot diverge in kind, only in timing.
2. **Replay never calls a model.** Model output enters the game only as
   events already in the log (`Asked`, `Spoke`, `Bound`, and the rest), so
   reopening the store replays the same voyage with no model calls. Every
   model-driven choice has a scripted temperament as fallback, which is
   also the whole policy in the simulator and the tests.
3. **An `Int64`-only core, with proved arithmetic.** Every quantity in
   `core` is `Int64`, fixed-point where fractional, so the js client and
   the native server compute bit-identical results; floats live only in
   rendering. The arithmetic kernels sit in `core/math`, a
   `proof_enabled` package checked by `moon prove`.

The package table and the sections after it are the reference form of those
three claims.

## packages

| Package       | Targets   | Role                                                                  |
| ------------- | --------- | --------------------------------------------------------------------- |
| `core/math`   | js native | Verified arithmetic kernels (`moon prove`). Proof-friendly code only. |
| `core`        | js native | Events, state, the transition function, wire types, optimistic sync.  |
| `ships`       | js native | Routes and their float plans, ship profiles, the worlds, the choice of next world and the itinerary older logs flew, the reckoning in the worlds' frame, the ship's scripted turn. |
| `sim`         | js native | The crossing simulator: scenarios, crew policies, batches, voyages.   |
| `store`       | native    | sqlite event log; replays through `core` on open.                     |
| `api`         | native    | Moonback routes over `store`.                                         |
| `cmd/server`  | native    | Server entry: opens the store, serves the API and static assets.      |
| `words`       | js native | Every sentence a player reads or hears, and each happening's priority. |
| `speech`      | native    | The ship speaks: which happening earns a line, its prompt, the speaker. |
| `mind`        | native    | The ship decides: its asks, refits and promotions, by model, with the temperament as fallback. |
| `cmd/browser` | js        | Rabbita (TEA) client.                                                 |
| `cmd/speak`   | native    | Flies one ship through a crossing in memory and prints its lines.     |
| `cmd/audition`| native    | Puts every ship's character in the same moments; prints choices and lines. |
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
bobzhang/minijinja (model calls and prompt templates).

## sync

The client and server run the same `core`. `State::apply` is the only
transition: the server uses it to validate and commit, the client to predict.

The client applies its proposals locally for immediate feedback and sends them
one at a time. It learns its officer from `GET /api/session`; a proposal
carries that crew id, and the server refuses one that names another officer.
Each receipt, accepted or refused, carries the server's
snapshot, which the client adopts as confirmed state. Sending one at a time is
what makes this sound: each receipt's snapshot contains exactly the client's
earlier proposals. `Optimistic::resync` ignores snapshots while a proposal is
in flight for the same reason.

On a transport error the client drops its pending proposals and reloads the
snapshot, so queued input is lost. Fixing that needs idempotent proposals on
the server.

Only the server moves game time. Clients propose an `Intent`; the log holds
`Event`, which adds the server's `Tick(at)` in Unix seconds, `Departed`,
`Docked`, and the ship's `Asked`, `Refitting`, `Promoted`, `Cruising`, `Bound` and `Spoke`. Before anything it writes,
the store appends a tick at the wall clock, so a receipt's snapshot may
include a tick and the ship's response to the proposal as well as the
proposal itself; `seq` counts them all. Between receipts the client applies
a local `Tick(at=now)` to its prediction for display and never proposes one.
It also polls the snapshot, since the ship acts on its own.

`cmd/server` runs one clock per ship in `@ships.fleet()`. Each sleeps
until its berth's next advance (`Berth::next_advance`), then calls
`Store::advance` for that ship. A berth has a `lag`, its own second in the
minute: it advances at that second when idle, and that long after each of
the ship's instants (`Profile::wake`: a rate boundary, arrival, or the
stores loaded in port). Ships with the same instant, such as ships departing
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

Measured 2026-10-28 with `cmd/speak`, two runs of one Tigress crossing,
12 lines: writing a line with `muse-spark-1.3` took 2.8 to 8.8 s, and
gating it 2.1 to 4.6 s, so a line lands 6 to 12 s after what prompted it.
The server's speakers print each line's times.

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
- `GET /api/session` returns `@core.Session`, the officer this client acts
  as and the ship they are aboard, if any (`Store::aboard`). A client with
  no ship shows the ships to choose from. A first visit mints a token and an officer and sets `session` as an
  HttpOnly cookie; later visits return the same officer. The cookie is
  `HttpOnly` and `SameSite=Lax`, and `Secure` unless `routes` is called with
  `secure=false` for plain-http development. The token never appears in a
  snapshot or the log, because both publish crew ids.
- `GET /api/ships` returns `Array[@core.Listing]`, in order of commission:
  each ship's whereabouts, the world it is at or left from and the one it
  is bound for, if chosen, how far along its leg it is (`run`, in
  thousandths), and how many officers are aboard (`@ships.listing`), which
  `@words.listing_sentence` renders. The fleet map on the Voyage page uses
  `run` to place every ship.
- `GET /api/ships/:id/snapshot` returns `@core.Snapshot`.
- `GET /api/ships/:id/story?after=seq` returns `@core.Story`: the ship's
  happenings after `seq`, and whether it is writing a line.
  Both the snapshot and the story answer 403 when the session's officer is
  aboard a different ship: the fleet list is all a player may know of a
  ship they are not aboard.
- `POST /api/ships/:id/proposals` takes `@core.Proposal` and returns
  `@core.Receipt`. It acts as the session's officer: no session is a 401, and
  a proposal naming another officer is a 403. A proposal for a ship the
  officer is not aboard while they are aboard another is also a 403, since
  the refusal receipt would otherwise carry that ship's snapshot. An unknown
  ship is a 404. A body naming a server event fails to decode and gets a 400.
- `GET /admin` is an HTML page of the whole game: every ship, every
  officer with a session, each ship's lines, log and its mind's recent
  thoughts, which players never see. It takes HTTP basic auth against
  `ADMIN_USER` (default `admin`) and `ADMIN_PASSWORD`, and answers 404
  when `ADMIN_PASSWORD` is unset. Thoughts live in memory, so a restart
  empties them.
- `POST /admin/hails`, with the admin's credentials, sends a hail: text
  for each ship named to tell its crew of, in its own voice. It takes
  `{"ships": [id, ...], "text": ...}` as JSON, or the admin page's form,
  and refuses the whole request if any ship is unknown or does not speak
  (`Store::minded`). A post whose `Origin` names another site is a 403,
  since browsers send cached basic credentials with cross-site forms.
- A session is not a seat. Nothing limits how many officers join a ship.
  An officer serves on one ship at a time: `Store::propose` refuses a
  proposal from an officer aboard another ship with `AboardAnother`, since
  no one ship's log can see the others.

## store

Every accepted event is a row in `event` with the ship's id and a json
body: crew intents, ticks, departures and dockings, and the ship's asks, refits,
promotions, cruises, chosen worlds and spoken lines. Each ship's log begins with `Commissioned`, which carries the ship
and the name of the profile it flies by, so replay needs nothing outside
the log. The server commissions every berth in `@ships.fleet()` that isn't
in service yet when it starts. A tick is written for each ship at least once
a minute while the server runs. The events one call appends go in one
transaction. A snapshot's `seq` is the log position of the ship's latest
row, so it rises but skips. Each ship's in-memory snapshot is its rows
replayed through `State::apply` and is rebuilt on open. So is its story:
the happenings `@core.happenings` derives from each row and the states
either side of it, kept in memory and never written. Logs that predate a change to when events land are kept aside in
`event_before_*` tables and not replayed, since replaying them would give
different arrivals; the current `event` table is the only log replayed.
Sessions live in a `session` table beside the log: a random token and the
officer it names. They are not events, do not replay, and are restored with
the database. Hails live in a `hail` table beside it too, so their text
never reaches a snapshot or a story: the ship, the text, when it was sent,
and either the log position of the line that answered it (`spoke`) or why
none did (`silence`). `Store::speak` marks a hail answered in the same
transaction as its line.
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

## story and speech

Phases, demands and refits change inside ticks, so most of what a player
is told is not a row. `@core.happenings(before, event, after)` derives it,
the store keeps each ship's story, and the client reads it from `/story`
for the log, "while you were away" and announcements.

`cmd/server` runs one speaker and one mind per ship whose `captain.md`
and `voice.md` are approved, when a `MODEL_API_KEY` is set. Every 3 s the
speaker weighs the happenings it has not seen (`@speech.worth`), and for
one that earns a line it renders `content/speech/` with the ship's faces,
the sentences a player reads, the crew by handle (`@speech.roster`), and
what the mind chose and why. It writes the line with `WRITER_MODEL`, gates
it with `GATE_MODEL`, and appends `Spoke(line, about)` through
`Store::speak`, which takes only `@llm_gate.Cleared` text: the gate's
`Gate::clear` is the only way to make one. The model may reply `PASS`, and
a line that opens like, or reuses most of the words of, one of the ship's
last five is dropped (`@speech.repeats`). A failed, blocked, passed or
repeated line leaves nothing.

Before weighing happenings, the speaker answers the ship's oldest open
hail, even within the quiet. It renders the same prompt with the hail in
place of a happening, recounting the whole crossing, and tells the model
not to pass. The line goes through the same tidying, repeat check and gate,
and its `Spoke` has `about` `@speech.HAILED` (-1), a position no happening
has, so players hear it at `Announce`. A hail that gets no line is marked
silent with the reason, which the admin page shows; it is not retried. After a line the ship keeps quiet for 15
minutes except for departures, arrivals, promotions, new demands, new
officers and its choice of next world, whom it greets knowing only whether it has carried them before. The
speaker waits while the mind is deciding, so a line can speak to the
choice. The runtime image copies `content/` for this.

## the ship's mind

A minded ship (`Store::mind`) makes its choices by model. The clock and
`Store::propose` leave its turn out (`Profile::due(minded=true)`), and the
mind, polling every 3 s, takes a turn whenever the ship's moment has
changed since it last asked, or a refit landed with nothing queued. It
renders `content/mind/turn.md` with the readout, the crew by handle, the
crossing's happenings and its own last thoughts, asks `MIND_MODEL` for
`{"ask", "refit", "thought"}`, and appends the acts through
`Store::decide`, which drops the turn if the moment passed while the model
thought. At arrival it renders `content/mind/muster.md` and appends the
promotions the model names, as far as `@ships.allowed` lets them stand,
then docks with the stores for the next leg, through `Store::muster`. Once
each port stay, soon after docking, it renders `content/mind/cruise.md`
with the launch as players read it, the hull, the officers' named posts,
the last crossing's happenings and, for each world in `@ships.choices`,
its distance, when the ship would leave for it, the ship's past dockings
there (from its story), the other ships in port there or bound there, and
for each of `@ships.cruises` the hours aboard, the coast's unmended erosion
and the hull hands that hold it even. It asks for
`{"course", "cruise", "ask", "thought"}`, and appends `Bound`, `Cruising`
and the port's `Asked` through `Store::cruise`, which does nothing once the
ship has departed and drops a world not in `@ships.choices`. An unreadable
course falls back to `Temperament::course`, and an unreadable ask to
`Temperament::port_ask`. The nearest world named at a second port running
also gives way to `Temperament::course` (`Temperament::ranging`), and the
model's thought is dropped, since it argues for the other world. The
thought is never shown to players; the speaker hears it.

While underway, a ship whose officers are bottom-heavy
(`@ships.bottom_heavy`: three in four are ensigns, and one has served the
six hours an ensign needs) holds a promotion cycle when no turn is due, at
most once every 30 minutes. The cycle renders the muster prompt with
`arrived` false, appends what the model names through `Store::promote`,
which never docks, and falls back to the longest-serving ensign.

A failed, unreadable or late reply (2 minutes for a turn or a cruise, 3
for a muster) falls back to the temperament and `@ships.promotions`. An
unminded ship's clock chooses the temperament's world as it docks and sets
its cruise just before it departs. A minded ship still unbound when its
stores are loaded is bound by temperament, which can resize the stores and
delay departure. If the mind never
musters, the clock promotes by script and docks `MIND_WAIT` (5 minutes)
after arrival. Until a turn lands the ship asks for nothing, and the Log
says it is weighing a choice (`Story.thinking`). Replay reads only the
log, so it never calls the model.

`cmd/audition` flies the Tigress with four scripted officers to a
departure, a demand, the coast, an arrival and the next port, and gives each moment to
every ship's character and values, sampled, on the models it is given.
Replies are cached in `.cache/llm`. Run it with `moon run cmd/audition`; `cmd/speak` flies one ship the same way.
