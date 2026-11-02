# all ships are brothers

A hard scifi idle rpg where players crew on sentient starships based on *The Water Margin* and operated by live LLMs. The game is live at https://brothership.fly.dev.

Ships are characters first: each one is written from a figure in the novel, decides for itself what it needs from its crew, speaks in its own voice, and promotes the officers it trusts. Every line a ship writes is checked against a written content policy by a second model before a player sees it. The game is built around screen-reader and large-text play; the log of sentences is the game, and the visual layout is a presentation of it.

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
| [gameplay](docs/gameplay.md) | the player loop, posts, crossings, demands, port |
| [architecture](docs/architecture.md) | packages, sync, API, store, verification, cross-target determinism |
| [accessibility](docs/accessibility.md) | screen reader, announcements, contrast |
| [design](docs/design.md) | palette, type scale, layout, fonts, hanzi setting |
| [content](docs/content.md) | what the ships may and may not say, and how that is enforced |
| [cast](docs/cast.md) | how a ship's character is made: entry, portrait, faces |
| [glossary](docs/glossary.md) | terms used in the code and docs |
| [translation](docs/translation.md) | ship names and titles in English and Chinese |
| [simulator](docs/simulator.md) | the crossing simulator and its scripted crews |
| [tools](docs/tools.md) | hearing ships choose and speak on real models before players do |
