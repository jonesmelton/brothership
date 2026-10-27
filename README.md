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

## Crossing simulator

```sh
ulimit -n 4096
warren dev --direct --browser-entry cmd/harness --port 4311  # http://127.0.0.1:4311
```

Runs one crossing many times under scripted crews and shows the results
against the design's targets. See [docs/sim.md](docs/sim.md). Without the
`ulimit`, warren's file watcher fails with `Too many open files`.
