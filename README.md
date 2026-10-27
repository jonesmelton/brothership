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
