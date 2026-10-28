# cast

A ship starts from its pennant. Given one, the pipeline drafts its
`entry.md` from what the repo already knows about it plus the model's
knowledge of the Water Margin, the author checks and corrects the draft
against the novel, and the approved entry feeds everything after: a
private portrait, and once you approve one, the ship's faces (`captain`,
`voice`, `voyage`). Background: [docs/cast.md](../../docs/cast.md).

Run from the repository root. The Meta Model API key comes from
`MODEL_API_KEY`, or `~/.config/brothership/meta-api.key`. Get one at
dev.meta.ai. Team usage and billing are at dev.meta.ai/usage; there is no
usage API, so the per-draft cost printed by `run` (list rates in
`llm/llm.mbt`) is the local record.

```sh
# 1. draft the entry for a new ship (or write entry.md by hand instead)
moon run cmd/cast -- run HS-242

# 2. read content/cast/ships/HS-242/drafts/entry.*.md, check against the
#    novel, then approve one and correct entry.md by hand
moon run cmd/cast -- approve HS-242 entry 2

# 3. optional: steer the portrait before it's drafted
echo "She, not he. Funnier than it knows." > content/cast/ships/HS-242/notes.md

# 4. draft the portrait from the entry (or everything missing: run)
moon run cmd/cast -- run HS-242

# 5. read content/cast/ships/HS-242/drafts/portrait.*.md, then pick one
moon run cmd/cast -- approve HS-242 portrait 2

# 6. draft the faces from the approved portrait, then approve each
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

Canon files (`entry.md`, `portrait.md`, `captain.md`, ...) are never
overwritten by a run. Edit them by hand freely; the entry is expected to
need it, since its drafts are the model recalling the novel. To redraft
one, delete it and `run` again. If you change `entry.md`, `notes.md` or
the portrait, `status` marks the files made from them as stale.

A ship's directory is named for its pennant, and `run` creates it when it
drafts the entry. `pennants.tsv` maps each pennant to the ship's Chinese
conventional name and its English epithet. A ship's title is pennant plus
conventional name plus epithet (`EF-147 顧大嫂 The Tigress`). Ships
themselves use epithets only, in any language. `moon run
scripts/pennants.mbtx` rebuilds the file, keeps every pennant already in it,
and warns about directories that are not in it.

Asking a ship a question isn't built yet.
