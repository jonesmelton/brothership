# cast

Each ship in `ships/<pennant>/` starts as `entry.md`. The pipeline drafts a
private portrait from it, and once you approve one, drafts the ship's faces
(`captain`, `voice`, `voyage`) from that. Background: [docs/cast.md](../../docs/cast.md).

Run from the repository root. The Meta Model API key comes from
`MODEL_API_KEY`, or `~/.config/brothership/meta-api.key`. Get one at
dev.meta.ai. Team usage and billing are at dev.meta.ai/usage; there is no
usage API, so the per-draft cost printed by `run` (list rates in
`llm/llm.mbt`) is the local record.

```sh
# 1. optional: steer the portrait before it's drafted
echo "She, not he. Funnier than it knows." > content/cast/ships/HS-242/notes.md

# 2. draft what every ship is missing (or name ships: run HS-242 HS-367)
moon run cmd/cast -- run

# 3. read content/cast/ships/HS-242/drafts/portrait.*.md, then pick one
moon run cmd/cast -- approve HS-242 portrait 2

# 4. draft the faces from the approved portrait, then approve each
moon run cmd/cast -- run HS-242
moon run cmd/cast -- approve HS-242 captain 1
moon run cmd/cast -- approve HS-242 voice 2
moon run cmd/cast -- approve HS-242 voyage 1

# see what's approved, edited by hand, or stale
moon run cmd/cast -- status
```

Each `run` makes `samples` drafts per stage (set in `cast.json`, along with
models and limits) and prints each draft's cost and check problems. Replies
are cached in `.cache/llm`, so rerunning an unchanged prompt is free; add
`--replay` to use only the cache.

Canon files (`portrait.md`, `captain.md`, ...) are never overwritten by a run.
Edit them by hand freely. To redraft one, delete it and `run` again. If
you change `entry.md`, `notes.md` or the portrait, `status` marks the files
made from them as stale.

A ship's directory is named for its pennant. `pennants.tsv` maps each pennant
to the hero's Chinese name and sobriquet; look a ship up there before
creating its directory. `moon run scripts/pennants.mbtx` rebuilds the file,
keeps every pennant already in it, and warns about directories that are not
in it.

Asking a ship a question isn't built yet.
