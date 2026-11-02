# simulator

A browser page that flies one crossing many times under different crews and
shows where the results land against the design's targets. It runs the game's
own rules: `@core.Crossing` is the same code the server and client will use,
and `sim` only adds policies, a clock and reporting.

```sh
warren dev --direct --browser-entry cmd/harness --port 4311
```

The page starts on the mixed-crew scenario, runs 50 seeded crossings, and
opens the median one. Change a parameter and press **Run batch**.

The same simulator prints as text, which is quicker to read and to diff
between tunings:

```sh
moon run --release cmd/survey --target native -- all 20
```

The first argument picks a section and the second the seeds per batch:

| section | prints |
|---|---|
| `envelopes` | each ship's fastest and slowest hours and spread at 3 to 60 ly |
| `scenarios` | every scenario's batch on the plain ship |
| `ships` | the solo and mixed crews on each ship |
| `policies` | the solo player under each policy, as artist and as engineer |
| `launches` | each ship's port stay at 20 ly by crew in port: minutes, and hull at departure |
| `voyages` | six legs on each ship, docking and launching between them |
| `careers` | six-leg voyages by the solo player's policy and craft |
| `story` | one thoughtful player's check-ins, with what each choice would do |
| `all` | every section |

## what the page shows

| section | shows |
|---|---|
| Envelope | fastest and slowest arrival at each distance, against the 6–16 hour target and the 2.5× spread limit |
| Batch | arrival distribution, lowest-hull distribution, the share of dead check-ins, where crew time went, and the fastest and slowest runs |
| Run | a timeline of phase, rapidity, setting, hull, crew per post, forecast arrival and check-ins, what became of each demand, refits landed and works made, then every decision with its watch, its effect on arrival, its undominated choices and the news it came back to |

A **dead check-in** is a player's check-in where no choice of post could move
the arrival forecast by five minutes (`DEAD_LEVERAGE`). It is the page's
measure of whether the player had a decision. It counts arrival only: a
check-in that exists to save the hull is not dead, and this misses it.

## policies

Policies stand in for people and for the ship. They are scripted because the
harness can't afford model calls, and because a policy has to be understandable
when it loses.

| policy | behaviour |
|---|---|
| selfish | always its craft |
| driver | always the drive |
| mender | always the hull |
| cooperative | the drive while the drive fires, else its craft |
| careful | cooperative, but the hull below half |
| random | any post, uniformly |
| hastener | whichever post arrives soonest, recomputed every check-in |
| saboteur | whichever post arrives latest |
| dutiful | an open demand's post, else what the ship asks for, else cooperative |
| steady | ship posts only: an open demand's, else the ask, else the drive while it fires and the hull otherwise. Recruits use it |
| thoughtful | every post, with and without a watch and a standing order, scored on arrival, hull, its own works and regard, and the ship's refits |

Cooperative, careful, dutiful and thoughtful players leave a standing order
for the next phase: craft when the coast begins, drive at turnover. Careful
crew take the hull below half and stay until three quarters, so they do not
change post at every band edge.

The ship is a policy too. Its temperament (`ships/profiles.mbt`) picks the next
refit when one lands and what to ask for whenever a phase changes, a demand
opens or closes, or the hull changes band.

Hastener and saboteur are the two ends of a search over post sequences. Every
one they find is inside the envelope (see `sim/sim_test.mbt`), which is why the
envelope is safe to show players.

## add a scenario

Add an entry to `scenarios()` in `sim/scenarios.mbt`. A scenario names a ship
profile from `profiles()` in `ships/profiles.mbt`. An `Actor` is a name, a policy,
a craft, a cadence and a joining time; `Reactive` is an NPC that acts whenever a
rate changes, `Every` is a player that checks in on an interval with jitter.
