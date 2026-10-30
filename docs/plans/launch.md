# plan: the launch

Replace the fixed 10-minute port stay with a launch the crew can speed up.
Departure waits on one stock, the **stores**, that hands on the drive post
load. While the ship waits, hands on the hull post work the **yard**, which
restores hull. Port dockhands work both stocks at a floor rate, so a ship
with no crew, or only absent ones, still leaves. An active crew leaves much
sooner.

What the crew decides is whether to leave sooner or mend more. Every hand on
stores brings the departure closer and shortens the time the yard has.
Every hand in the yard leaves with more hull and leaves later. The bold
Scorpion will ask for stores and the careful Tigress for the yard, and the
speaker can argue for its ship's choice.

Read these first: `AGENTS.md`, `docs/architecture.md` (this changes `core`,
the store's contents and the clock), `docs/gameplay.md` (port, posts,
standing orders, the hull), `docs/decisions.md`, `docs/sim.md`.

## facts established before writing this

Checked on 2026-10-29 against the repo at `afda139`.

- The port is `Leg::InPort(since~)` (`core/state.mbt`). There is no
  `Crossing` in port: officers are `State.officers`, each with
  `Officer.post`, the post to take at departure. `Docked` sets that from the
  post held at arrival, so an absent officer's post already carries into
  port. `Posted` and `Left` in port change it. Watches, crafts, making
  banked work and orders are refused in port (`NotUnderway`).
- `Cruising(cruise~)` is a ship event allowed only in port.
- `Crossing::dock` (`core/crossing.mbt`) adds a flat
  `PORT_REPAIR = 250_000_000` (a quarter hull) to the ship.
- `ships/clock.mbt`: `Profile::due` departs once
  `s.at >= since + PORT_STAY`, `Profile::wake` returns that instant, and
  `listing` reports `InPort(departs=since + PORT_STAY)`.
  `PORT_STAY = 600` is in `ships/profiles.mbt`.
- `words/words.mbt:211` prints the departure from `since + PORT_STAY`.
- `Store::muster` (`store/store.mbt:334`) appends `Docked` itself after the
  mind's promotions.
- Orders: `Ordered` refuses `phase == Arrived` (`core/crossing.mbt:731`).
- Recruits in the live game are only `Ship.recruits`, a count. They hold no
  hands. Only the simulator flies them, as steady actors (`sim/run.mbt:177`).
- Migrations: `store/schema.mbt`, now at `user_version = 10`. The pattern
  for keeping old logs aside is `alter table event rename to
  event_before_<x>` followed by a fresh `event` table.

## decisions this plan makes

State them in the PR. Propose `docs/decisions.md` entries for the first two.

- **Only stores gate departure; the yard works only until it.** `apply`
  rejects `Departed` while stores are left (`NotReady`). So a log with an
  early departure doesn't replay, and every log from before this change is
  kept aside as `event_before_launch`.
- **A floor rate makes every launch finish.** The dockhands work stores and
  yard at fixed rates whoever is aboard. Nothing a player does, or fails to
  do, can hold a ship in port longer than the floor allows.
- **The server sizes the stores.** `Docked(stores~)` carries the stock for
  the next leg, worked out from its light-years in `ships`, because `core`
  doesn't know the worlds. Like `Departed(plan~)`, it is a server event.
- **Port work is officers on their named post.** In port, `Officer.post` is
  the post an officer works now as well as the one taken at departure. There
  are no hands, watches, banks or regard in port in this plan.

## the rules

New in `core`, all `Int64`:

```
pub(all) struct Port {
  since : Int64        // docked at, Unix seconds
  stores : Int64       // left to load, in quarter-hand-ticks
}
Leg::InPort(port~ : Port)
```

Per tick in port:

- stores fall by `DOCKHANDS + 4 × (officers posted to Drive)`, down to 0;
- the hull rises by `YARD_FLOOR + fit.repair × (officers posted to Hull)`,
  up to `HULL_FULL`. `fit.repair` is per hand per tick, as in the crossing,
  so plating pays in the yard too. The yard writes to `State.ship.hull`.
- officers on the craft post do nothing in port.

Both stocks are linear between events. `Port::ready_at(state)` is
`since`-relative arithmetic: ticks to empty at the current rate, using
`@math.ticks_to_empty`. Rates change only at `Posted`, `Left`, `Leaving`,
`Signed` and docking, so no boundaries are needed beyond the stores running
out and the hull filling.

`Crossing::dock` drops `PORT_REPAIR`. `Docked(stores~)` builds
`InPort(port={ since: at, stores })`. `Departed` checks `stores == 0`.

Starting numbers, for the harness to tune:

| constant | value | meaning |
|---|---|---|
| `DOCKHANDS` | 4 | one hand's quarters on stores |
| `YARD_FLOOR` | 35_000 | about a quarter hull over 2 hours |
| stores per leg | `2 × HOUR × HAND × ly / 20` | 2 crew-hours at 20 ly |

These give, at 20 ly: an idle ship departs in 2 hours with about the
quarter hull it gets today; one officer on stores halves that; four leave
in about 24 minutes with about 5% from the yard. Target 30 to 40 minutes
for an active crew of four.

### orders into port

Allow `Ordered(phase=Arrived, post~)`. It fires at arrival like any order,
so the post carries into port through `Docked`. This is how a player who
won't be around at arrival says "hull while in port". It needs no new port
state.

## steps

Tests first in each step. `moon test -u` fills snapshots; read every
changed snapshot before accepting it.

1. **`core`: the port as stocks.**
   - Tests in `core/state_test.mbt`:
     - an empty ship's stores run out at exactly `stores / DOCKHANDS` ticks;
     - an officer posted to the drive in port speeds that, and one posted
       to the hull raises the hull without moving the departure;
     - an officer posted to craft changes neither stock;
     - `Departed` before the stores run out raises `NotReady`;
     - the hull caps at `HULL_FULL`;
     - `Port::ready_at` matches the first tick at which `Departed` is
       accepted.
   - Property in `core/sync_test.mbt`: one tick of `n` seconds lands on
     the same state as `n` ticks of one second, in port.
   - Then: add `Port` and `Docked(stores~)`, remove `PORT_REPAIR`, give
     `Tick` in port the yard and stores, add `NotReady`, and add
     `Port::ready_at` and `Port::rates` for the interface.
   - Update `core/story.mbt`: `Docked` derives as before. Add
     `Loaded` (the stores ran out) as a happening, Log-only.
2. **`core`: orders for arrival.** Test that an order for `Arrived` fires
   at arrival and the officer's port post is the ordered post. Then lift
   the refusal at `crossing.mbt:731`.
3. **`ships`: sizing and the clock.**
   - Add `Profile::stores(legs~)` from the next leg's light-years.
   - Tests in `ships/ships_test.mbt`, changing the existing `PORT_STAY`
     ones:
     - `due` departs at `ready_at` and not a tick before;
     - `wake` returns `ready_at`;
     - `listing` reports it.
   - Then: replace `PORT_STAY` in `due`, `wake` and `listing`, and push
     `Docked(stores=self.stores(...))`.
   - The temperament's turn learns to ask in port: bold and sly ask for
     the drive, careful for the hull, social for the emptier post. It
     reconsiders at docking and when stores run out, which keeps "only
     when something happens".
4. **`store`: archive and muster.** Add the migration renaming `event` to
   `event_before_launch` and recreating `event`. Test it in
   `store/schema_wbtest.mbt` like `event_before_dust`. `Store::muster`
   takes the stores size from the profile when it appends `Docked`.
   `Store::propose` must run `respond` in port so asks land.
5. **`mind` and `speech`.**
   - `content/mind/turn.md` gets a port moment: stores left, the hull, the
     ready time, and the choice between leaving sooner and mending more.
     `Profile::due(minded=true)` leaves the port turn to the mind, as it
     does underway.
   - The speaker gets the stores running out as a happening it may speak
     to. That stays under the 15-minute quiet; the departure line stays
     exempt.
6. **`sim`: a port policy.**
   - Actors and recruits take a port post: steady actors follow the ask,
     others keep their post.
   - `Voyage` flies the launch between legs instead of docking straight
     into the next.
   - Re-run `cmd/survey` and record in `docs/sim.md` the port time and
     hull at departure for idle, solo and four-officer crews on each ship.
   - Check that the check-in figures in `docs/gameplay.md` still hold.
7. **`words` and `cmd/browser`.**
   - The port line reads the ready time and the yard: "In port at Tigray.
     Stores load in about 40 minutes; the yard has the hull at 62%."
   - The forecast changes at once when a post changes, which is the
     launch's whole feedback.
   - Offer the arrival order beside the other standing orders.
   - Follow `docs/accessibility.md`: `Loaded` is Log-only, and departure
     keeps its priority.
8. **Docs.** `docs/gameplay.md` "port" and the posts table, the
   `architecture.md` store paragraph (`event_before_launch`), the glossary
   (**launch**, **stores**, **yard**, **dockhands**), and `docs/sim.md`.

Steps 1 to 4 leave the server deployable with scripted ships. Do them in a
worktree, because step 1 breaks `ships`, `store` and `words` until step 4.

## left out

- **Regard for port work.** Without it the ship's ask in port only moves
  recruits in the sim. Add a port tally settled into records at
  `Departed`, weighted by the ship's values. It's the first follow-up if
  playtests show officers ignoring the ask.
- **Crafts in port.** Engineers could build at double rate in the yard, so
  coils land before the plan is fixed. That needs banks in port.
- **Watches in port.**
- **Live recruits holding posts.** Today they hold none anywhere.
- **Destination choice.** The launch gives it a window, but `Departed`
  would have to name its leg.

## open questions

- Are 2 hours idle too long against crossings of 6 to 16 hours? It adds
  about 15% to a 13-hour crossing. Tune it in step 6.
- Should the stores scale with light-years or the plan's burn? Light-years
  is simpler, and the range is only 13.8 to 25.4.
