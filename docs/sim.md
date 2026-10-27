# crossing simulator

A browser page that flies one crossing many times under different crews and
shows where the results land against the design's targets. It runs the game's
own rules: `@core.Crossing` is the same code the server and client will use,
and `sim` only adds policies, a clock and reporting.

```sh
warren dev --direct --browser-entry cmd/harness --port 4311
```

The page starts on the mixed-crew scenario, runs 50 seeded crossings, and
opens the median one. Change a parameter and press **Run batch**.

## what the page shows

| section | shows |
|---|---|
| Envelope | fastest and slowest arrival at each distance, against the 6–16 hour target and the 2.5× spread limit |
| Batch | arrival distribution, lowest-hull distribution, the share of dead check-ins, where crew time went, and the fastest and slowest runs |
| Run | a timeline of phase, rapidity, setting, hull, crew per post, forecast arrival and check-ins, then every decision with its effect on arrival |

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

Hastener and saboteur are the two ends of a search over post sequences. Every
one they find is inside the envelope (see `sim/sim_test.mbt`), which is why the
envelope is safe to show players.

## add a scenario

Add an entry to `scenarios()` in `sim/scenarios.mbt`. An `Actor` is a name, a
policy, a cadence and a joining time; `Reactive` is an NPC that acts whenever a
rate changes, `Every` is a player that checks in on an interval with jitter.

## what it found so far

At 40,000 g and 24,000 γ cap:

- spread stays under 2.5× from about 4.5 ly out; a 2 ly hop reaches 2.74×, and
  at 300 ly staffing changes nothing (1.07×). The spread is a short-hop
  phenomenon, and the floor setting of 0.35 is what sets its size;
- only 20 ly falls wholly inside 6–16 hours. A 60 ly crossing at full burn is
  26 hours, so either the target or the map has to move;
- a full crew saturates the drive: with `drive_needed = 4`, eight crew on the
  drive is past the point of any further gain, and a quarter of player
  check-ins in the mixed scenario cannot move arrival at all;
- the hull barely registers in a mixed scenario: crew repair outruns wear, and
  the lowest hull reached is 54%. The worn-hull scenario is what makes it
  matter.
