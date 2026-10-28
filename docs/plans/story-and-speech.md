# plan: the story, and the ship speaks

Built 2026-10-28. What shipped is described in "story and speech" in
[architecture](../architecture.md); this plan keeps the reasoning.

Two features that share one foundation: the log a player reads, and the
ship's own lines written by a model.

## the problem

Most of what a player would call an event never appears as a row.
Phases begin, demands open, close and are missed, and refits land inside
`Tick`, because the crossing steps through boundaries on its own. The
client sees snapshots only and diffs two of them (`news` in
`cmd/browser`). There is nothing to build a log or announcements from, and
nothing to prompt the ship to speak.

## the story

A **happening** is something a player would be told: derived from one row
and the states either side of it by a pure function in `core`,
`happenings(before, event, after)`. The kinds: departed, phase began,
arrived, docked, demand opened, met or missed, refit landed, ask changed,
crew took a post or left, watch stood, work finished, and the ship spoke.

- The store derives happenings as it replays and as it commits, and keeps
  each ship's story in memory beside its snapshot. Nothing derived is
  written to sqlite; the log stays the only source of truth.
- `GET /api/ships/:id/story?after=seq` returns the entries after `seq`
  (each with its row's `seq` and the state's `at`) and whether the ship is
  speaking now.
- Sentences for happenings live with the other sentences. Those move from
  `cmd/browser` to a `words` package (js native), because the server needs
  them too: they are the readout the ship's prompt is written from.

## the client

- **While you were away** summarizes the story after the last `seq` this
  browser saw, which replaces the stored state and the state diff.
- **Log**: the latest entries, newest first, each a sentence and how long
  ago.
- **Announcements**: two live regions, polite and assertive, present from
  first render. New entries since the last poll are spoken by priority:
  interrupt (a demand opening), announce (the ship's lines, phases,
  departure and arrival, demands met or missed, refits, your own watch and
  works), or log only (crew moving, asks). A setting with three choices,
  everything, urgent only or nothing, is kept in `localStorage`. A ship's
  line takes the priority of the happening it answers.

## the ship speaks

- `Event::Spoke(line~, about~)`: a server event with the line and the `seq`
  of the happening it answers. It changes no state.
- A package `speech` (js native) holds the pure parts: which happening
  deserves a line (departures, phases, arrival, demands, refits; at most
  one line per 15 minutes except at departure and arrival), and the
  prompt: the ship's `captain.md` and `voice.md`, the setting, the current
  state in the same sentences a player reads, the recent story, and the
  happening to answer. Under 40 words, plain text, epithets only.
- `cmd/server` runs one speaker per ship that has faces: it waits for a
  happening worth a line, generates with `meta:muse-spark-1.3`, checks the
  line with `llm/gate`, and appends `Spoke` through the store. A failed or
  blocked line leaves nothing, and the scripted ask still stands. Without a
  `MODEL_API_KEY` the speakers do not start.
- Only ships with `captain.md` and `voice.md` speak. Today that is EF-147.

## risks

- Generation latency is unmeasured. The design tolerates seconds; the
  speaker logs each call's time so the first real numbers get recorded.
- Live regions on iOS Safari are unreliable. Not testable here; needs a
  device.
- Deriving happenings on every row costs a state diff per tick at replay.
  Cheap at today's log sizes; measure if open slows.
