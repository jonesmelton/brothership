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

## tuning record

Numbers moved out of [gameplay](gameplay.md): starting points and survey
results the harness was tuned against, not how the game plays. Targets are
stated with each table; the simulator above is how they were measured.

### crossings

Targets: a typical crossing takes 6 to 16 hours, the longest about 30.
Staffing should change a crossing's length by at most 2.5×. The first
session happens in port, because no crossing is shorter than its burn.

At 40,000 g, these hold. Crossing hours by drive setting:

| | setting 0.35 | 0.65 | 1.0 |
|---|---|---|---|
| 5 ly, cap 24k | 13.7h | 8.2h | 6.0h |
| 20 ly, cap 24k | 19.2h | 13.7h | 11.5h |
| 60 ly, cap 50k | 23.3h | 17.4h | 15.0h |

Staffing matters about 2.3× on short hops and 1.4× on long ones, where the
coast dominates. Time at home is about one year per light-year whatever the
crew do.

### check-ins

In the simulator a player checking in every 3 hours, give or take 2, came
back to something new on about 80% of returns. About 90% of check-ins
offered two or more choices that no other choice beat on arrival, hull,
works, regard and refits together (`moon run cmd/survey --target native`).

### cruises

A solo player with two NPCs on 20 ly
(`moon run cmd/survey --target native cruises`):

| ship | cruise | hours, median | lowest hull | works, tenths |
|---|---|---|---|---|
| a plain ship | full | 12.0 | 62% | 29.7 |
| a plain ship | 4/5 | 13.6 | 65% | 39.4 |
| a plain ship | 3/5 | 16.4 | 71% | 55.2 |
| HS-212 The Twin-Tailed Scorpion | full | 10.9 | 50% | 14.0 |
| HS-212 The Twin-Tailed Scorpion | 3/5 | 14.8 | 53% | 46.1 |

Below 8 ly, a ship with coils fitted spends more of the crossing in the
burn, and staffing stretches it past 2.5×. The map's hops run 8 to 30 ly,
so every leg holds the targets above.

### worlds

| world | star | | Kerala | Tigray | Oaxaca | Occitan | Three Tyrants |
|---|---|---|---|---|---|---|---|
| Kerala | τ Ceti | | | 24.2 | 20.0 | 15.7 | 29.6 |
| Tigray | 70 Ophiuchi | | 24.2 | | 21.7 | 13.8 | 15.0 |
| Oaxaca | δ Pavonis | | 20.0 | 21.7 | | 25.4 | 15.2 |
| Occitan | 61 Cygni | | 15.7 | 13.8 | 25.4 | | 26.3 |
| The Three Tyrants | Gliese 667 | | 29.6 | 15.0 | 15.2 | 26.3 | |

Before ships chose, they flew the itinerary Kerala, Occitan, Tigray,
Kerala, Oaxaca, Tigray, Occitan, Oaxaca, The Three Tyrants, Tigray,
Occitan, The Three Tyrants and round again, and their logs name no worlds:
`None` in those fields resolves to the itinerary's leg after `crossings`
dockings (`@ships.leg`).

### crafts and refits

On the Flea, which proposes coils first, a solo engineer's six-leg voyage
took about 79 hours aboard against 96 for a solo artist, both at the Flea's
three-fifths cruise, not counting port. On the plain ship, which proposes
baffles and plating, engineers bought hull and no time.

### demands

In the simulator, crews missed 44 to 56% of demands, fewest on the
Scorpion and most on the Flea.

### port

At 20 ly from half a hull, on every ship (`cmd/survey launches`):

| crew in port | minutes in port | hull at departure |
|---|---|---|
| nobody | 120 | 75% |
| 1 on the drive | 60 | 63% |
| 1 on the hull | 120 | 90 to 98% |
| 4 on the drive | 24 | 55% |
| 3 on the drive, 1 on the hull | 30 | 60 to 62% |
| 2 on the drive, 2 on the hull | 40 | 68 to 74% |

### starting profiles

Starting profiles, from `ships/profiles.mbt`:

| ship | accel, g | γ cap | drive hands | wear | repair | values: drive, hull, craft | temperament |
|---|---|---|---|---|---|---|---|
| a plain ship | 40,000 | 24,000 | 4 | 30,000 | 28,000 | 2, 2, 1 | careful |
| EF-147 The Tigress | 38,000 | 24,000 | 5 | 24,000 | 32,000 | 1, 3, 2 | social |
| HS-212 The Twin-Tailed Scorpion | 46,000 | 26,000 | 3 | 42,000 | 24,000 | 3, 1, 1 | bold |
| EF-287 The Flea on the Drum | 42,000 | 20,000 | 3 | 34,000 | 20,000 | 1, 1, 3 | sly |

The same solo crew on a 20 ly crossing at full cruise arrived in 11.0 hours
on the Scorpion with the hull down to 50%, and in 13.0 hours on the Tigress
with the hull at 80%. The Flea made the most works
and twice the regard for crafters: its crafters reached rank 3 within six
crossings while its drivers stayed at rank 1.

