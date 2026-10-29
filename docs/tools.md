# tools

Two command-line tools for hearing how ships choose and speak on real
models before anything reaches players. Both run in memory, never touch a
game database, and cache every reply in `.cache/llm`, so a rerun of the
same prompts is free and `--replay` makes no calls at all.

Both need a Meta Model API key in `MODEL_API_KEY` or
`~/.config/brothership/meta-api.key`, except with `--replay`. Run them from
the repository root, because they read `content/`.

## cmd/audition: every ship in the same moment

`cmd/audition` flies the Tigress through one crossing with four scripted
officers, stops at fixed moments, and gives each moment to every ship's
character and values. Each ship's mind is sampled several times, and each
ship then writes one line about the moment, gated. Use it to compare
characters, prompts or models on identical state: if the ships choose the
same thing for the same reasons, the prompt or the model is flattening them.

The officers are the same in every run:

| handle | officer | does |
| --- | --- | --- |
| A | ann | takes whatever post the ship asks for |
| B | bo | keeps the drive, on a 4-hour watch |
| C | cy | engineer at crafts, never answers an ask |
| D | di | joins the hull 2 hours in on a watch, breaks it at 4 hours for crafts |

| scenario | stops when |
| --- | --- |
| `departure` | an hour out of port |
| `demand` | the crossing's first demand opens |
| `coast` | the coast begins |
| `arrival` | the ship arrives; it chooses promotions instead of a turn |

| flag | default | meaning |
| --- | --- | --- |
| `--mind M` | `meta:muse-spark-1.3-contributor` | model that makes choices |
| `--writer M` | the `--mind` model | model that writes the line |
| `--gate M` | `meta:muse-spark-1.3-contributor` | model that gates the line |
| `--samples N` | 3 | choices sampled per ship and moment |
| `--replay` | off | use only cached replies; a miss is an error |
| scenario names | all four | which moments to run |

For each scenario it prints the readout and roster the model sees, then for
each ship a tally of its choices (`the hull ×2, the drive ×1`), each
sample's private reason, and its line. The line follows the first sample's
ask. A line the gate blocks, the model passes on, or that repeats is shown
in parentheses with the reason. The last line is the estimated spend.

All four scenarios on the contributor tier take about 10 minutes and cost a
few cents:

```sh
moon run cmd/audition --target native -- > _build/audition-spark.md
```

The same on Muse Wonder cost $0.92 with 3 samples, on 2026-10-28. Run this
before accepting a prompt change, since weaker models converge:

```sh
moon run cmd/audition --target native -- --mind meta:muse-wonder-1.0 --samples 3 > _build/audition-wonder.md
```

The demo setup, with choices on the contributor tier and lines on Wonder:

```sh
moon run cmd/audition --target native -- --writer meta:muse-wonder-1.0 arrival demand
```

To print a run again after editing only the formatting of the output:

```sh
moon run cmd/audition --target native -- --replay --samples 3
```

Changing a prompt in `content/mind/` or `content/speech/` changes every
call's cache key, so the next run calls the model again. `--samples` adds
or reuses samples: samples 1 to 3 are the same calls whatever `N` is.

## cmd/speak: one ship, one whole crossing

`cmd/speak` flies one ship from port to its first docking with the same
four officers, its mind deciding and its speaker speaking as the server
would, on a simulated clock. It prints the timeline the player would see
with the ship's lines indented, and a `mind` line for each choice with its
reason and how long the model took. Use it to see a character's arc: what
it neglects, whom it favours, whether it repeats itself.

| argument | default | meaning |
| --- | --- | --- |
| ship | `tigress` | berth id: `tigress`, `scorpion` or `flea` |
| `--mind M` | `meta:muse-spark-1.3-contributor` | model that makes choices |
| `--writer M` | the `--mind` model | model that writes lines |
| `--replay` | off | use only cached replies |

The gate is always `meta:muse-spark-1.3-contributor`. A crossing takes 10
to 20 minutes on the contributor tier, since every choice and line waits on
the model in turn.

```sh
moon run cmd/speak --target native -- flea > _build/speak-flea.txt
```

The demo setup:

```sh
moon run cmd/speak --target native -- --writer meta:muse-wonder-1.0 scorpion > _build/speak-scorpion.txt
```

Everything on Wonder, about 25 Wonder calls:

```sh
moon run cmd/speak --target native -- --mind meta:muse-wonder-1.0 tigress
```

A rerun with the same prompts and models replays the same crossing from the
cache. Lines marked `speech ... kept quiet`, `repeats itself` or `blocked`
were dropped, as they would be on the server.

## the server's models

The server reads the same choices from its environment, set in `fly.toml`:

| variable | used for |
| --- | --- |
| `MIND_MODEL` | the ship's choices: asks, refits, promotions |
| `WRITER_MODEL` | the lines players read |
| `GATE_MODEL` | the content gate on every line |

Each falls back to `MODEL`, then to `meta:muse-spark-1.3-contributor`.
`make deploy` ships the committed `fly.toml`, so to put Wonder on the lines:

1. Set `WRITER_MODEL = "meta:muse-wonder-1.0"` under `[env]` in `fly.toml`.
2. Commit it and run `make deploy`.
3. Check the boot log for the models in use:

   ```sh
   fly logs | grep "models:"
   ```

   It prints `models: mind meta:muse-spark-1.3-contributor, writer meta:muse-wonder-1.0, gate meta:muse-spark-1.3-contributor`.
