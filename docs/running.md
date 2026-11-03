# running the game

How to run the game locally, check it, deploy it, and hear ships on real models before players do. For how the game plays see [gameplay](gameplay.md); for packages, sync, the API and the store see [architecture](architecture.md).

## requirements

- The [MoonBit toolchain](https://www.moonbitlang.com/download/)
- warren: `moon install moonbit-community/warren`
- z3, cvc5 or alt-ergo on `PATH`, for the proofs in `make check`

## run locally

```sh
make dev    # http://127.0.0.1:4300, live reload
make build  # dist/server.exe and frontend assets
make test   # tests on js and native
make check  # type check, tests on both targets, proofs
make sim    # crossing simulator at http://127.0.0.1:4311
```

`make` is the entrypoint. Do not add targets unless asked.

No model is required to run the game. Ships speak only if a `MODEL_API_KEY` is set (a Fly secret in production); without one the server starts, scripted temperaments make the ships' choices, and the server logs that ships will not speak. `cmd/speak` and `cmd/audition` also read the key from `~/.config/brothership/meta-api.key` (see [tools](tools.md)).

## Meta models

Three Meta models sit in the path from a player's input to the text they read. Input itself never waits on a model: a proposal is applied and committed at once, and model text arrives later as its own event in the log.

| model | role | where it sits |
| --- | --- | --- |
| `meta:muse-spark-1.3` (`MIND_MODEL`) | the ship's choices: what it asks for, which refit it proposes, whom it promotes, its next world and cruise | the ship's mind on the server (`mind`), polled between ticks |
| `meta:muse-wonder-1.0` (`WRITER_MODEL`) | the lines players read | the speaker (`speech`), writing a line for a happening that earns one |
| `meta:muse-spark-1.3` (`GATE_MODEL`) | checks every line against `content/gate/policy.md` before a player sees it | `llm/gate`, after the writer and before the line is appended as a `Spoke` event; only its `Cleared` type can reach the log |

The deployed server runs the `fly.toml` values, which name the contributor tier of Muse Spark 1.3 for the mind and the gate (`meta:muse-spark-1.3-contributor`); the boot log prints the models in use (`fly logs | grep "models:"`). Each of `MIND_MODEL`, `WRITER_MODEL` and `GATE_MODEL` falls back to `MODEL`, and then to `meta:muse-spark-1.3-contributor` in `cmd/server`.

The cast that gives each ship its character is also drafted on `meta:muse-wonder-1.0` (see [cast](cast.md)). A call that fails, is blocked, or is passed on leaves no message; the event that prompted it still stands, and a scripted temperament covers any choice the model would have made. `cmd/speak` and `cmd/audition` run the same path in memory so ships can be heard before players are (see [tools](tools.md)).

## deploy

```sh
make deploy # ships HEAD to Fly.io; refuses uncommitted tracked changes
```

Production is one Fly machine and one volume, never autostopped, at https://brothership.fly.dev. The database is `/data/brothership.sqlite`; Litestream replicates it to Tigris every 30 s and a boot with no database restores from it (see [architecture](architecture.md)). Model keys and the admin password are Fly secrets, not `fly.toml` values:

| secret | effect |
| --- | --- |
| `MODEL_API_KEY` | ships speak and think; without it they run on temperaments |
| `ADMIN_PASSWORD` | enables `GET /admin`; without it that route answers 404 |
| `ADMIN_USER` | the admin user name, default `admin` |

The admin page shows every ship, every officer with a session, each ship's lines, log and its mind's recent thoughts, which players never see. `POST /admin/hails` sends a hail for named ships to answer in their own voice.

## tools

| tool | use |
| --- | --- |
| `cmd/speak` | flies one ship through a crossing in memory and prints its lines |
| `cmd/audition` | puts every ship's character in the same moments; prints choices and lines |
| `cmd/gate` | checks messages, or `content/gate/samples`, against the gate policy |
| `cmd/cast` | the cast pipeline CLI over `content/cast` |
| `cmd/survey` | prints the crossing simulator's batches, comparisons and voyages |
| `cmd/harness` | the simulator in a browser page (`make sim`) |

Flags, scenarios and costs are in [tools](tools.md) and [simulator](simulator.md).
