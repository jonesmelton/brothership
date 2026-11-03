# gameplay

How the game plays: the player loop, posts, crossings, crafts, the ship, demands and port. Tuning tables and survey results are in [simulator](simulator.md); the rules core that makes the crossing computable is under [rules core](#rules-core).

## the player

A player is one crew member, an **officer**: one soul. A ship carries up to
about ten officers and as many NPC crew as it needs. NPCs keep a ship with one
officer playable, stand in for officers in the simulation harness, and are
what deliveries recruit.

An officer serves on one ship at a time. A new player chooses a ship from
the fleet, in port or underway, and signs on. They stay aboard through each
port stay and take their post again at departure. They leave when the ship
docks if they asked to leave after the voyage or did nothing during it, or
at once if they leave in port, and then choose a ship again. Standing down
from a post leaves them aboard.

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
(see [demands](#demands)).

## a check-in

A returning player first hears what happened while they were away: phase
changes, demands opened or closed, refits landed, their own watch stood and
works finished. Then they have up to six choices, each on its own timescale:

| choice | event | lasts | reaches |
|---|---|---|---|
| post | `Posted` | until changed | arrival and hull, for everyone |
| watch | `Watched` | 1 hour or more; the interface offers up to 12 | a quarter more from this hand; regard |
| standing order | `Ordered` | until its phase begins: the coast, the approach or arrival | the post taken at the phase change, or worked in port |
| make banked work | `Made` | at once | the ship's refit, or one's own works, at 100% to 150% of the bank |
| craft | `Crafted` | until changed | where the next making goes |
| refit, for engineers | `Refitting` | until it lands | the ship, for good |

Demands set deadlines on posts between check-ins, and docking carries each
crossing into the next.

How often a check-in offers a real choice is measured, not asserted: see
"check-ins" in [simulator](simulator.md).

## the crossing

Proper time aboard is wall-clock time. A crossing has three phases:

1. **Burn.** Rapidity rises at a rate set by the drive. The drive wants hands.
2. **Coast.** The ship runs at its cruise, a share of its γ cap that it
   chose in port. Drive crew make no difference, but the medium ahead
   erodes the hull, so hands split between the hull and their crafts.
3. **Approach.** The ship brakes to rest. The drive wants hands again.

So each phase change is a reason to check in and change post.

A typical crossing takes 6 to 16 hours. Staffing changes its length by at
most about 2.5×, and time at home is about one year per light-year whatever
the crew do. The measured tables are under "crossings" in
[simulator](simulator.md).

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

On the coast the hull erodes instead, at a rate that grows with the square of
the pace (`Plan::erosion`): the gas and dust ahead strike with an energy and
a flux that both grow with γ. At γ 24,000 the coast erodes `EROSION`, three
quarters of the wear at full burn. Over a whole coast the erosion grows with
γ, since a faster coast is a shorter one, so a slower cruise saves hull in
proportion. A coast neglected at full cruise drops the hull a band or two,
and the approach that follows burns at the lower cap.

### the cruise

The ship chooses its cruise in port for the next crossing (`Cruising`), from
`@ships.cruises`: its full γ cap, four fifths or three fifths. A slower
cruise arrives later, erodes less, and gives crafters more hours before
port. Time at home does not change. Measured cruise outcomes are under
"cruises" in [simulator](simulator.md).

A minded ship chooses by model (see "the ship's mind" in
[architecture](architecture.md)); otherwise, and when the model fails, by
temperament: bold at full, careful at four fifths or three fifths below 60%
hull, social at full or four fifths below 80% hull, sly at three fifths.
The scripted ships in the simulator fly each leg of a voyage at their
temperament's cruise.

Hands are counted in quarters: a crew member is 4 and one standing a watch
is 5, so `drive_crew` and the hull's repair are sums of quarters.

The hull's band, which sets the cap, falls as soon as the hull drops below
the band's edge and rises again only 5% above it (`BAND_MARGIN`). Without
the margin a ship mending at an edge dropped a band, wore less at the lower
cap, climbed back over the edge, and repeated every tick.

The map's hops run 8 to 30 ly, so every leg holds those targets.

## the worlds

Five settled worlds, each around a real star 11 to 24 ly from the Sun,
placed at the star's J2000 position (`ships/worlds.mbt`). Four are named
for places; The Three Tyrants is named for the three stars of Gliese 667.

Every pair is 13.8 to 29.6 ly apart. The five lie within 0.8 ly of one
plane, which is why the Voyage page can draw them on a flat map, true to
0.1 ly; the Sun is 7.6 ly off it. The full distance table is under
"worlds" in [simulator](simulator.md).

Each ship chooses where it goes next, in port (`Bound`), from any world but
the one it is at and the one it came from, so it never flies straight back
(`@ships.choices`). After a crossing under eighteen light-years it ranges:
worlds nearer than that are not choices, so it never makes two short
crossings running. Eighteen divides the map's neighbours, 13.8 to 15.7 ly
apart, from the next hop at 20.0.

A minded ship's model chooses in its cruise turn, soon
after docking, from each world's distance, how soon the ship would leave
for it, how often and how lately it has docked there, which other ships
are in port there or bound there, and the hours aboard and hull worn at
each cruise, and a sentence from its temperament saying where it leans. If
the model names the nearest open world at a second port running, the ship
leaves by temperament instead (`Temperament::ranging`), because models left
alone take the nearest whatever the character. The ship then tells the crew.
An unminded ship chooses by
temperament at docking: a bold ship the farthest world, a careful one the
nearest, a sly one the second farthest, and a social one any, by its seed.
A minded ship whose mind never chose leaves by temperament once its stores
are loaded.

Stores are sized by the leg chosen. Docking loads them for the world the
temperament would choose, and choosing another resizes them; what is
loaded already counts toward any leg. A ship entering service is at Kerala
and loads its first ten minutes of stores wherever it goes.

The log records each world chosen by name, and the ship carries where it
is, where it is bound and where it came from (`Ship.from`, `bound`,
`came_from`).

The worlds share one rest frame, so the years a crossing takes pass alike
at origin and destination, and come within a thousandth of a year of the
leg's light-years whatever the crew do. No world keeps a clock: see
the reckoning in `ships/reckoning.mbt`.

## crafts

A player's craft decides what their hours on the craft post make. They can
change it at any time. Smoothly taking in new players matters more than
guarding against switching craft to optimize. Crafters of the same craft at
work together each make a quarter more for every other one, up to double.

| craft | makes | benefits |
|---|---|---|
| engineer | refits | the whole ship, for good |
| artist | works of 6 crew-hours, delivered at port | the maker's record; recruits for the ship |

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
land nothing during the crossing.
Their banks are made at 100% when the ship docks, so the refit is fitted for
the next crossing.

Each payoff belongs to a different person, so crew depend on each other.
Core counts crew-hours for a work; the model will write a work's title and
description and decides nothing.

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
crossings and most on long hauls. They raise the erosion of a coast at full
cruise by the same fifth, so a ship with coils that will not mend coasts
slower and keeps less of their gain. Measured engineer and artist voyages
are under "crafts and refits" in [simulator](simulator.md).

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
the coast on a hop too short to reach the cap, lapses at turnover. An order
for arrival names the post to work in port: "hull while in port" for a
player who will not be around when the ship docks.

Before orders, players who crafted through the coast left the approach at
the drive's floor until they returned, and the coast forecast read about 3
hours late on a 20 ly crossing. With orders it matches arrival.

## the ship

The ship is the language model. It:

- **asks** for volunteers in character. Its character decides when and for
  what: a bold ship asks for the drive, a careful one for the hull.
- **chooses** where it goes next, in port, and tells the crew. See
  [the worlds](#the-worlds).
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
  that loses junior officers can stay topheavy. Rank grants no authority
  and no longer any limit on a watch.
  Regard accrues for each quarter-hand-tick on a useful post: the drive
  while it fires, the hull while it is short of full or a breach is open,
  and any craft. It is weighted by the ship's values, doubled on the post
  the ship asks for, and doubled again on a post an open demand needs.
- **cruises**: in port it chooses how fast to coast the next crossing,
  trading hours aboard against hull and craft time.
- **speaks**: arrivals, departures, promotions, and notice of who stood a
  watch.

The ship sets one rate, its cruise, and only in port. Its other choices
are what to ask, what to propose, what to refit, and how it treats crew.
The numbers underway come from posts.

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
| `Dust` | hull | coast | 3 to 6 crew-hours | hull loses 1/5 | nothing more |

A demand in a firing phase ends with the phase, so driving harder leaves less
time to meet it. Posts held while away count, so nothing depends on being
present at the right moment. Miss rates are under "demands" in
[simulator](simulator.md).

The coast's demand is a hazard, not something found on the way, because at
a γ of tens of thousands the ship can match velocity with nothing. A
microgram of dust at γ 24,000 strikes with about 2 TJ, half a kiloton.

## port

Arrival docks the crossing into the ship that leaves (`Crossing::dock`):

- each crew member's regard, finished works and held rank go to their
  record, and part-finished work carries over;
- every 3 works delivered across the crew bring a recruit, up to 6.
  Recruits work ship posts only and make no works, so recruits do not breed
  recruits;
- refits stay fitted, and coils change the next crossing's plan;
- the ship chooses its next world and tells the crew; the crew have no
  say in the choice.

Then the **launch**. The ship departs once its **stores** for the next leg
are loaded: two crew-hours for every 20 light-years. Officers stay on their
named posts in port, and in port the posts do other work:

| post in port | does |
|---|---|
| drive | loads stores at one hand's rate, so the ship leaves sooner |
| hull | works the **yard**, mending the hull at the ship's repair rate, until the ship leaves |
| craft | nothing |

The port's **dockhands** load stores at one hand's rate and mend about a
quarter hull over two hours whoever is aboard, so a ship with nobody aboard,
or only absent officers, still leaves. Nothing a crew does, or fails to do,
holds a ship in port longer than the dockhands take. The choice is whether
to leave sooner or mend more: every hand on stores brings the departure
closer and shortens the yard's time; every hand in the yard leaves with more
hull, and later. The ship asks once each port stay, at docking: bold and
sly ships for stores, careful ones for the yard while the hull is short,
social ones for the emptier post. A newly commissioned ship loads ten
minutes of stores before its first departure.

Measured port stays by crew in port are under "port" in
[simulator](simulator.md).

The ship's launch line reads the forecast, which moves at once when a post
changes: "Stores load in about 45 minutes, and the ship departs then. The
yard has the hull at 50%, and 60% by then."

Then the ship departs, and the new world gives everything a new meaning.

## ships

Which ship a player crews changes the crossing. A ship's kinematics and
fittings come from its character, and its values decide which work it
notices. The starting profiles and the same crew flown on each ship are
under "starting profiles" in [simulator](simulator.md).

## rules core

Each phase is a stock that changes linearly, so the crossing is a set of linear stocks and stays in `Int64`:

- **burn**: rapidity η rises at `a * setting`;
- **coast**: distance left falls at a constant rate, and the hull erodes at
  one;
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
