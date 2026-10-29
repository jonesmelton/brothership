# gameplay

The player's loop, and the rules core it implies. Numbers here are starting
points for the harness to tune, not targets; the targets are in each section.

## the player

A player is one crew member, an **officer**: one soul. A ship carries up to
about ten officers and as many NPC crew as it needs. NPCs keep a ship with one
officer playable, stand in for officers in the simulation harness, and are
what deliveries recruit.

## the core action: posts

Every crew member, player or NPC, always holds one **post**, and keeps it while
away. A post is either work for the ship or work for themselves:

- **Ship posts**, the drive and the hull, benefit everyone aboard. More hands on
  the drive burn harder and bring everyone to port sooner. Hands on the hull
  offset the wear that hard driving causes.
- **Your craft** is your own work: things the ship carries and delivers, or
  improvements to the ship itself.

Every hour a player gives goes to the ship or to themselves. With several
players aboard this is a public-goods game, and the setting already supports
it: a ship never orders crew, so it can only ask, and remember who answered.

Changing post is the thin verb. Its feedback is immediate: taking the drive
moves the arrival forecast at once ("four of nine on the drive, arriving in
about 11 hours").

### why posts and not events

Earlier prototypes had the ship decide how to handle events and the players
act on its decisions. That put the decision with the AI and the player
downstream of it, and resolved each event alone, so none could matter much.
Nothing the player built compounded.

Posts move the interaction into the economy, which always runs. Interaction
is as frequent as the crossing's phases and the crew's own choices, not as
frequent as events. Events still happen, but as demands on the same hours
(see [events](#events)).

## a check-in

A returning player first hears what happened while they were away: phase
changes, demands opened or closed, refits landed, their own watch stood and
works finished. Then they have up to six choices, each on its own timescale:

| choice | event | lasts | reaches |
|---|---|---|---|
| post | `Posted` | until changed | arrival and hull, for everyone |
| watch | `Watched` | 1 hour or more; the interface offers up to 12 | a quarter more from this hand; regard |
| standing order | `Ordered` | until the next phase begins | the post taken at the phase change |
| make banked work | `Made` | at once | the ship's refit, or one's own works, at 100% to 150% of the bank |
| craft | `Crafted` | until changed | where the next making goes |
| refit, for engineers | `Refitting` | until it lands | the ship, for good |

Demands set deadlines on posts between check-ins, and docking carries each
crossing into the next.

In the simulator a player checking in every 3 hours, give or take 2, came
back to something new on about 80% of returns. About 90% of check-ins
offered two or more choices that no other choice beat on arrival, hull,
works, regard and refits together (`moon run cmd/survey --target native`).

## the crossing

Proper time aboard is wall-clock time. A crossing has three phases:

1. **Burn.** Rapidity rises at a rate set by the drive. The drive wants hands.
2. **Coast.** The ship runs at its γ cap, and everyone's speed is the same.
   Drive crew make no difference, so hands go back to their crafts.
3. **Approach.** The ship brakes to rest. The drive wants hands again.

So each phase change is a reason to check in and change post.

Targets: a typical crossing takes 6 to 16 hours, the longest about 30. Staffing
should change a crossing's length by at most 2.5×. The first session happens in
port, because no crossing is shorter than its burn.

At 40,000 g, these hold. Crossing hours by drive setting:

| | setting 0.35 | 0.65 | 1.0 |
|---|---|---|---|
| 5 ly, cap 24k | 13.7h | 8.2h | 6.0h |
| 20 ly, cap 24k | 19.2h | 13.7h | 11.5h |
| 60 ly, cap 50k | 23.3h | 17.4h | 15.0h |

Staffing matters about 2.3× on short hops and 1.4× on long ones, where the
coast dominates. Time at home is about one year per light-year whatever the
crew do.

The drive setting comes from staffing, with diminishing returns so that one
crew member matters on a small ship:

```
setting = 0.35 + 0.65 * min(1, sqrt(drive_crew / drive_needed))
```

The 0.35 floor means a ship nobody staffs still arrives. `drive_needed` is per
ship, about 4 to start.

The hull wears faster the harder the ship drives (about `setting²` per hour)
and is repaired by hull crew. Damage lowers the highest setting the drive can
reach, so neglecting the hull makes later burns slower.

Hands are counted in quarters: a crew member is 4 and one standing a watch
is 5, so `drive_crew` and the hull's repair are sums of quarters.

The hull's band, which sets the cap, falls as soon as the hull drops below
the band's edge and rises again only 5% above it (`BAND_MARGIN`). Without
the margin a ship mending at an edge dropped a band, wore less at the lower
cap, climbed back over the edge, and repeated every tick.

The map's hops run 8 to 30 ly. Below 8 ly, a ship with coils fitted spends
more of the crossing in the burn, and staffing stretches it past 2.5×.

## the worlds

Four settled worlds, each around a real star 11 to 20 ly from the Sun,
placed at the star's J2000 position (`ships/worlds.mbt`):

| world | star | | Kerala | Tigray | Oaxaca | Occitan |
|---|---|---|---|---|---|---|
| Kerala | τ Ceti | | | 24.2 | 20.0 | 15.7 |
| Tigray | 70 Ophiuchi | | 24.2 | | 21.7 | 13.8 |
| Oaxaca | δ Pavonis | | 20.0 | 21.7 | | 25.4 |
| Occitan | 61 Cygni | | 15.7 | 13.8 | 25.4 | |

Every pair is 13.8 to 25.4 ly apart, inside the 8 to 30 ly a hop may be, so
any leg holds the crossing's targets. The four lie within 0.4 ly of one
plane, which is why the Voyage page can draw them on a flat map without
lying; the Sun is 7.6 ly off it.

Ships fly the itinerary Kerala, Occitan, Tigray, Kerala, Oaxaca, Tigray,
Occitan, Oaxaca and round again: every pair, two of them twice, since no
tour of four worlds flies each pair once. A ship is commissioned at Kerala,
and its leg after `crossings` dockings is `@ships.leg(crossings)`. The log
records the plan of each departure but not its worlds, so reordering the
itinerary renames every leg in flight.

The worlds share one rest frame, so the years a crossing takes pass alike
at origin and destination, and come within a thousandth of a year of the
leg's light-years whatever the crew do. No world keeps a clock: see
research/liveship-travel-math.md, section 8.

## crafts

A player's craft decides what their hours on the craft post make. They can
change it at any time. Smoothly taking in new players matters more than
guarding against switching craft to optimize. Crafters of the same craft at
work together each make a quarter more for every other one, up to double.

| craft | makes | benefits | built |
|---|---|---|---|
| engineer | refits | the whole ship, for good | yes |
| artist | works of 6 crew-hours, delivered at port | the maker's record; recruits for the ship | yes |
| navigator | charts that add reachable destinations | the whole ship's choices | not yet |

Hours at the craft post accrue to a personal bank, counted in the same work
units as refits and works. Nothing is built while the player is away. On
return, the player makes the bank in one action (`Made`), and it goes into
their current craft at 100% to 150% of its size: an artist's works, or the
engineers' refit progress, which can land a refit at once. The percent is a
pure function of the ship's seed, the crew id and the tick of the making,
so a replay gives the same result. A bank is made only when asked for, with
two exceptions: a hand who leaves the crew, and every hand when the ship
docks, make theirs at 100%, so no hour is lost. Changing craft or post keeps
the bank, and it is made into whatever craft the hand holds at the time. A
making is allowed at any phase while aboard, including after arrival and
before docking. Ship posts do not bank.

Because refits land only when work is made, engineers who never check in
land nothing during the crossing, apart from the progress a met salvage adds.
Their banks are made at 100% when the ship docks, so the refit is fitted for
the next crossing.

Each payoff belongs to a different person, so crew depend on each other.
Works do not yet take inputs gathered in port: core counts crew-hours. The
model will write a work's title and description and decides nothing.

Engineers build one refit at a time. The ship proposes which, by
temperament, and engineers can choose another. Each refit has three levels,
and each level costs half again as much as the last.

| refit | effect | first level |
|---|---|---|
| `Baffles` | wear ×3/4 | 5 crew-hours |
| `Plating` | repair per hull hand ×5/4 | 4 crew-hours |
| `Injectors` | one fewer drive hand for full burn, down to 2 | 6 crew-hours |
| `Coils` | γ cap up by a fifth of the route's, from the next departure | 10 crew-hours |

The first three land mid-crossing and change rates at once. Coils change the
plan, which is fixed when the ship leaves port, so they pay off only on later
crossings and most on long hauls. On the Flea, which proposes coils first, a
solo engineer's six-leg voyage took 61 hours against 68 for a solo artist.
On the plain ship, which proposes baffles and plating, engineers bought hull
and no time.

## watches

A watch is a promise to hold the current post for a stated time, at least
1 hour. The rules set no upper limit; the interface offers 1, 2, 4, 8 or 12
hours, and rank does not limit a watch. A hand on watch counts as 5 quarters
instead of 4, on any post. A watch stood to its end earns an hour of regard
for each hour stood. A post change before the end breaks it and costs two
hours of regard for each hour already stood, never taking regard below zero.
Arrival ends every watch, paid for the part stood, so a watch that would run
past arrival costs nothing. A watch begun after arrival ends at once and
counts for nothing.

What the watch trades away is flexibility. A long watch on the drive that
runs past turnover keeps a hand on a post the coast does not need, unless a
standing order moves it.

## standing orders

A standing order names a post to take when a later phase begins: "craft when
the coast begins", or "drive at turnover". It fires at the phase boundary,
so a player who leaves during the burn crafts through the coast and is back
on the drive for the approach without checking in. A watch in progress
carries over to the new post. An order for a phase the plan skips, such as
the coast on a hop too short to reach the cap, lapses at turnover.

Before orders, players who crafted through the coast left the approach at
the drive's floor until they returned, and the coast forecast read about 3
hours late on a 20 ly crossing. With orders it matches arrival.

## the ship

The ship is the language model. It:

- **asks** for volunteers in character. Its character decides when and for
  what: a bold ship asks for the drive, a careful one for the hull.
- **proposes** two or three destinations within reach, with its reasons. The
  crew choose among them.
- **remembers** who answered. Each crew member's **regard** is computed in
  core from what they did, weighted by values authored per ship from its
  faces. Regard decides whom the ship may promote. Rank is public and spoken,
  and is held per ship in `Record.rank`, one of five: ensign, lieutenant
  junior grade, lieutenant, lieutenant commander or commander. `rank_floor`
  gives the highest rank a regard makes someone eligible for, at 0, 40, 120,
  280 and 500 hours of regard. A crew member new to a ship starts as an
  ensign. Rank moves only by a `Promoted` event, one step, when a crossing
  has arrived and before it docks. `@ships.promotions` chooses by total
  regard, the record's plus the crossing's, under the caps `rank_caps` sets:
  commander 1, lieutenant commander 2, lieutenant 3, lieutenant junior grade
  4 and ensign uncapped, counted among the officers aboard. The caps are
  fixed for now, whatever the officer count. Nobody is demoted, so a ship
  that loses junior officers can stay topheavy. Rank grants nothing yet: no
  authority, and no longer any limit on a watch. Add authority, such as
  setting the drive within the ship's tolerance, when a good candidate turns
  up.
  Regard accrues for each quarter-hand-tick on a useful post: the drive
  while it fires, the hull while it is short of full or a breach is open,
  and any craft. It is weighted by the ship's values, doubled on the post
  the ship asks for, and doubled again on a post an open demand needs.
- **speaks**: arrivals, departures, promotions, and notice of who stood a
  watch.

The ship never sets a rate. Its choices are what to ask, what to propose,
what to refit, and how it treats crew. The numbers come from posts.

The ship reconsiders what it asks for only when something has happened: a
phase change, a demand opening or closing, or the hull changing band. A
social ship in the simulator that asked for the emptiest post whenever a
hand moved, crewed by recruits who follow asks, sent itself and them from
post to post every tick. Asks are also speech, which
[accessibility](accessibility.md) treats as scarce.

## demands

A demand is a call for hours on one post before its phase ends. Each
crossing has one or two, fixed at departure from the ship's seed and
crossing count, so nothing a crew does rerolls them. Each opens when its
phase's stock is between a fifth and two thirds spent, so its window shrinks
and grows with the drive rather than with the clock.

| demand | post | phase | needs | if missed | if met |
|---|---|---|---|---|---|
| `Breach` | hull | burn or approach | 1.5 to 3 crew-hours | hull loses 25% | nothing more |
| `Flare` | drive | burn or approach | 2 to 4 crew-hours | hull loses 1/6 | nothing more |
| `Salvage` | craft | coast | 4 to 8 crew-hours | nothing | 3 crew-hours of refit progress |

A demand in a firing phase ends with the phase, so driving harder leaves less
time to meet it. Posts held while away count, so nothing depends on being
present at the right moment. In the simulator, crews missed 30 to 55% of
demands, most on the Scorpion and fewest on the Tigress.

## port

Arrival docks the crossing into the ship that leaves (`Crossing::dock`):

- each crew member's regard, finished works and held rank go to their
  record, and part-finished work carries over;
- every 3 works delivered across the crew bring a recruit, up to 6.
  Recruits work ship posts only and make no works, so recruits do not breed
  recruits;
- the yard restores a quarter of the hull;
- refits stay fitted, and coils change the next crossing's plan;
- the ship proposes destinations and the crew choose. How several players
  choose is still open, and none of it is built.

Not built yet: works raising their makers' standing at a world, and
gathering inputs for the next works.

Then the ship departs, and the new world gives everything a new meaning.

## ships

Which ship a player crews changes the crossing. A ship's kinematics and
fittings come from its character, and its values decide which work it
notices. Starting profiles for the playtest cast, from `ships/profiles.mbt`:

| ship | accel, g | γ cap | drive hands | wear | repair | values: drive, hull, craft | temperament |
|---|---|---|---|---|---|---|---|
| a plain ship | 40,000 | 24,000 | 4 | 30,000 | 28,000 | 2, 2, 1 | careful |
| EF-147 The Tigress | 38,000 | 24,000 | 5 | 24,000 | 32,000 | 1, 3, 2 | social |
| HS-212 The Twin-Tailed Scorpion | 46,000 | 26,000 | 3 | 42,000 | 24,000 | 3, 1, 1 | bold |
| EF-287 The Flea on the Drum | 42,000 | 20,000 | 3 | 34,000 | 20,000 | 1, 1, 3 | sly |

The same solo crew on a 20 ly crossing arrived in 10.5 hours on the
Scorpion with the hull down to 59%, and in 13.0 hours on the Tigress with
the hull at 88% and the fewest demands missed. The Flea made the most works
and twice the regard for crafters: its crafters reached rank 3 within six
crossings while its drivers stayed at rank 1.

## idle grammar

How the loop meets the [research](../research/Idle%20Games%20Research%20Dossier.html):

- **Rate is the emotional number**: arrival forecast, craft progress, hull,
  and γ for spectacle.
- **Walls branch into decisions**: a missing input, hull wear capping the
  drive, a destination out of reach. Each leads to a different post or craft.
- **Automation is earned relief**: NPC recruits fill ship posts as the ship
  grows, which eases the public-goods pressure.
- **Unfolding**: the game starts in port with only the drive post. Crafts open
  at the first coast, and other ships later.
- **Crossing as a run**: arrival settles everything and the new world changes
  its meaning. There is no prestige layer. The season is finite and authored.
- **Big numbers come from physics**: γ climbs into the tens of thousands, and
  decades pass at home in an hour. The economy stays small and countable.

## rules core

Each phase is a stock that changes linearly, so the crossing fits the
[idle core](../research/idle-core.md) model and stays in `Int64`:

- **burn**: rapidity η rises at `a * setting`;
- **coast**: distance left falls at a constant rate;
- **approach**: η falls to zero.

Rates change only at events in the log, such as a post change, so the state
between events is linear and splittable. Phase changes are the next event. A rate also changes at a boundary: a phase ends, the hull
changes band or fills, a demand opens or is met, a watch ends, a refit lands,
or a standing order fires. An idle crossing steps through a few dozen
boundaries, and a law in `core/crossing_test.mbt` holds it under 256. The
plan for each route fixes the burn's target η and the coast distance offline
in floats, and stores them as integers. The distance covered while burning
then does not depend on the setting. That approximation is acceptable for
order-of-magnitude physics. The renderer computes γ = cosh η and pace in
floats.

Language-model output, like ship asks, proposals and work descriptions, is
written to the log as events. Replay never calls a model. Each model-driven
choice has a scripted policy, used by the harness and as the fallback when a
call fails.

The idle core's "no background process" is given up, but not for the
rules: phase changes and deadlines need no scheduler, because any event,
including a tick, steps through them. The scheduler on the server exists so
the ship can speak, dock and depart at the right instant.

## left behind from the research

- **Stepped kinematics** (travel math §4–6): pressure drift, hysteresis and
  deterministic transcendental functions. Phases with linear stocks replace
  them.
- **Crossings of 2 to 8 days.** Too few port calls for one season. Proper
  time = wall time stays, and acceleration rises to 40,000 g.
- **The contract and payment formula.** Money doesn't fit near-utopian worlds.
- **Prestige layers and big-number types.**
- **Events as the main interaction.**

## out of scope for now

- Works crossing between ships through registers.
- Authority from rank beyond public standing.
- Ships meeting in port, and the cross-ship coordinate-time problem that
  registers and meetings raise. Each ship keeps its own calendar and worlds
  keep none.
