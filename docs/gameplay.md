# gameplay

The player's loop, and the rules core it implies. Numbers here are starting
points for the harness to tune, not targets; the targets are in each section.

## the player

A player is one crew member: one soul. A ship carries up to about ten players
and as many NPC crew as it needs. NPCs keep a ship with one player playable,
stand in for players in the simulation harness, and are what deliveries
recruit.

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

## crafts

A player's craft decides what their own hours make. They choose one before
their first departure and can change it at any time. Smoothly taking in new
players matters more than guarding against switching craft to optimize.

| craft | makes | benefits |
|---|---|---|
| engineer | ship upgrades: a higher γ cap, less hull wear | the whole ship, for good |
| navigator | charts that add reachable destinations | the whole ship's choices |
| artist, scholar | works, delivered at port | the maker's standing; recruits for the ship |

Each payoff belongs to a different person, so crew depend on each other. A
work is made from inputs the crafter has gathered in port. Two players working
together make more than either alone. Core computes a work's stats from its
inputs. The model writes its title and description and decides nothing.

## the ship

The ship is the language model. It:

- **asks** for volunteers in character. Its character decides when and for
  what: a bold ship asks for the drive, a careful one for the hull.
- **proposes** two or three destinations within reach, with its reasons. The
  crew choose among them.
- **remembers** who answered. Each crew member's **regard** is computed in
  core from what they did, weighted by values authored per ship from its
  faces. Regard sets **rank**, which is public and spoken. For now rank grants
  no authority. Add authority, such as setting the drive within the ship's
  tolerance, when a good candidate turns up.
- **speaks**: arrivals, departures, promotions, and notice of who stood a
  watch.

The ship never sets a rate. Its choices are what to ask, what to propose, and
how it treats crew. The numbers come from posts.

## events

An event is a demand for hours: "a breach needs 6 crew-hours before
turnover". It matters because the hours come from the drive or from someone's
craft. A deadline is a time in the crossing, not a window for a reaction. Any
post change made before the deadline counts, so nothing depends on being
present at the right moment.

Keep events to about one or two per crossing. Interaction doesn't depend on
them.

## port

Arrival settles the crossing:

- delivered works raise their makers' standing at that world, and bring NPC
  recruits to the ship;
- regard turns into rank, and the ship marks promotions;
- crew gather inputs for their next works, and may change craft;
- the ship proposes destinations and the crew choose. How several players
  choose is still open.

Then the ship departs, and the new world gives everything a new meaning.

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
between events is linear and splittable. Phase changes are the next event. The
plan for each route fixes the burn's target η and the coast distance offline
in floats, and stores them as integers. The distance covered while burning
then does not depend on the setting. That approximation is acceptable for
order-of-magnitude physics. The renderer computes γ = cosh η and pace in
floats.

Language-model output, like ship asks, proposals and work descriptions, is
written to the log as events. Replay never calls a model. Each model-driven
choice has a scripted policy, used by the harness and as the fallback when a
call fails.

The idle core's "no background process" is given up. A scheduler on the server
fires phase changes, deadlines and ship asks.

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
