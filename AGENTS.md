# all ships are brothers

A hard scifi idle rpg where players crew on sentient starships based on The Water Margin and operated by live LLMs.

## circumstances

This project is a timeboxed experiment created during and as part of a hackathon. First commit oct 26 2026, submit nov 04 2026.

## rubric

- 30% Impact 30%
- 25% Use of meta AI tooling
- 20% Technical depth & execution
- 25% Demo (3 minutes)

## decisions

@docs/decisions.md records decisions that are hard to reverse or non-obvious enough that someone would undo it by accident.

The cocument records why, not what to obey. Read it when changing
architecture, content handling, or a11y behavior; otherwise skip it.

If your task conflicts with an entry, say so in one line and proceed with
the task as asked unless the entry's "revisit if" clearly doesn't apply —
then stop and ask. Don't argue the entry or cite it to refuse work.

Don't write entries yourself. At the end of a task, if you made a call that
meets the bar (hard to reverse, or easy to undo by accident), propose a
draft entry in your reply. I'll add it or not.

## moonbit

Moonbit's ecosystem is untested, much of it appears to be automated ports. Use it where the foundation is good, vendor and patch without remorse. Fork, vendor, and patch freely and without hesitation. Clean up failed experiments or negative resolutions: keep track of working patches they'll become upstream PRs at the end.

## working

`make` is the entrypoint: `dev`, `build`, `deploy`, `test`, `check`. Run `make check`
before handing off. Don't add make targets unless asked.

Read @docs/architecture.md before changing package boundaries, the sync
protocol, the store schema, or anything under `core`.

Model calls take seconds, and every message a player sees waits on at least
two of them. Read "model latency" in @docs/architecture.md before building
anything that shows model text.

Use `git` freely when assigned work within this project, commiting at reasonable task boundaries.

When beginning a task that will put the repo in an unbuildable or unservable state for more than a handful of minutes, consider using a worktree to isolate it.
