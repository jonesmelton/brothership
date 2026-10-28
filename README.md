# all ships are brothers

A hard scifi idle rpg where players crew on sentient starships.

## Requirements

- [MoonBit toolchain](https://www.moonbitlang.com/download/)
- warren: `moon install moonbit-community/warren`
- z3, cvc5 or alt-ergo on `PATH` (for `make check`)

## Run

```sh
make dev    # http://127.0.0.1:4300, live reload
make build  # dist/server.exe and frontend assets
make test
make check  # fmt, type check, tests, proofs
```

The server stores its data in `brothership.sqlite` in the working directory.
Set `BROTHERSHIP_DB` to use another path, and `WARREN_HOST` / `WARREN_PORT`
to change the address.

## Deploy

The game runs at https://brothership.fly.dev: one machine in `ord`, with its
sqlite log replicated to Tigris by Litestream every 30 s.

```sh
make deploy  # ships HEAD; refuses uncommitted tracked changes
```

Provisioning, secrets and the restore drill are in
[docs/deploy-plan.md](docs/deploy-plan.md).

## Docs

[docs/README.md](docs/README.md) indexes the design and implementation notes.

## Crossing simulator

```sh
make sim    # http://127.0.0.1:4311, live reload
```

Runs one crossing many times under scripted crews and shows the results
against the design's targets. See [docs/sim.md](docs/sim.md).
