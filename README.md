# all ships are brothers

A hard scifi idle rpg where players crew on sentient starships based on *The Water Margin* and operated by live LLMs. The game is live at https://brothership.fly.dev.

Ships are characters first: each one is written from a figure in the novel, decides for itself what it needs from its crew, speaks in its own voice, and promotes the officers it trusts. Every line a ship writes is checked against a written content policy by a second model before a player sees it. The game is built around screen-reader and large-text play; the log of sentences is the game, and the visual layout is a presentation of it.

![The Tigress underway: masthead, latest line, and the readout](docs/ship-speaking.png)

*EF-147 The Tigress underway. The line under the masthead is the ship speaking in its own voice, after the gate has cleared it. The screenshot is a static capture of the live layout; the game itself is the sentences, playable without looking at the screen.*

## Meta models

Three Meta models sit in the path from a player's input to the text they read. Input itself never waits on a model: a proposal is applied and committed at once, and model text arrives later as its own event in the log.

| model | role | where it sits |
| --- | --- | --- |
| `meta:muse-spark-1.3-contributor` (`MIND_MODEL`) | the ship's choices: what it asks for, which refit it proposes, whom it promotes, its next world and cruise | the ship's mind on the server (`mind`), polled between ticks |
| `meta:muse-wonder-1.0` (`WRITER_MODEL`) | the lines players read | the speaker (`speech`), writing a line for a happening that earns one |
| `meta:muse-spark-1.3-contributor` (`GATE_MODEL`) | checks every line against `content/gate/policy.md` before a player sees it | `llm/gate`, after the writer and before the line is appended as a `Spoke` event; only its `Cleared` type can reach the log |

The cast that gives each ship its character is also drafted on `meta:muse-wonder-1.0` (see [cast](docs/cast.md)). A call that fails, is blocked, or is passed on leaves no message; the event that prompted it still stands, and a scripted temperament covers any choice the model would have made. These assignments are the `fly.toml` values the deployed server runs; `cmd/speak` and `cmd/audition` run the same path in memory so ships can be heard before players are (see [tools](docs/tools.md)).

## Run

Requirements: the [MoonBit toolchain](https://www.moonbitlang.com/download/), warren (`moon install moonbit-community/warren`), and z3, cvc5 or alt-ergo on `PATH` for `make check`.

```sh
make dev    # http://127.0.0.1:4300, live reload
make build  # dist/server.exe and frontend assets
make test
make check  # type check, tests on both targets, proofs
make sim    # crossing simulator at http://127.0.0.1:4311
make deploy # ships HEAD to Fly.io; refuses uncommitted tracked changes
```

Ships speak only if a `MODEL_API_KEY` is set (a Fly secret in production); without one the server starts and logs that ships will not speak.

## Docs

| doc | use it for |
| --- | --- |
| [gameplay](docs/gameplay.md) | how the game plays: the player loop, posts, crossings, port |
| [architecture](docs/architecture.md) | the three technical claims, then packages, sync, API, store, verification |
| [accessibility](docs/accessibility.md) | screen reader, announcements, contrast |
| [design](docs/design.md) | palette, type scale, layout, fonts, hanzi setting |
| [content](docs/content.md) | what the ships may and may not say, and how that is enforced |
| [cast](docs/cast.md) | how a ship's character is made: entry, portrait, faces |
| [glossary](docs/glossary.md) | terms used in the code and docs |
| [decisions](docs/decisions.md) | why hard-to-reverse choices were made |
| [translation](docs/translation.md) | ship names and titles in English and Chinese |
| [simulator](docs/simulator.md) | the crossing simulator, its scripted crews, and the tuning record from it |
| [tools](docs/tools.md) | hearing ships choose and speak on real models before players do |
