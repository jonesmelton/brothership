# architecture

## packages

| Package       | Targets   | Role                                                                  |
| ------------- | --------- | --------------------------------------------------------------------- |
| `core/math`   | js native | Verified arithmetic kernels (`moon prove`). Proof-friendly code only. |
| `core`        | js native | Events, state, the transition function, wire types, optimistic sync.  |
| `store`       | native    | sqlite event log; replays through `core` on open.                     |
| `api`         | native    | Moonback routes over `store`.                                         |
| `cmd/server`  | native    | Server entry: opens the store, serves the API and static assets.      |
| `cmd/browser` | js        | Rabbita (TEA) client.                                                 |

Stack: rabbita (frontend), warren (build and dev server), moonback on
moonbitlang/async (server), moonbit-community/sqlite3 (vendored sqlite,
async API), moonbitlang/quickcheck (property tests).

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

## api

- `GET /api/snapshot` returns `@core.Snapshot`.
- `POST /api/proposals` takes `@core.Proposal` and returns `@core.Receipt`.

## store

Every accepted event is a row in `event` with a json body. The in-memory
snapshot is the log replayed through `State::apply` and is rebuilt on open.
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
