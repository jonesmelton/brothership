# Cleanup recommendations

Kept in place because deleting or rewriting them outright would lose something load-bearing. Each item says what to change and why.

## Rewrite for judges

| file | change |
| --- | --- |
| `README.md` | Already trimmed to pitch, run commands, and a doc index. Add a screenshot or a short clip of a ship speaking, and one paragraph naming the Meta models in use (`meta:muse-spark-1.3` for choices and the gate, `meta:muse-wonder-1.0` for the lines players read) with where each sits in the path from input to shown text. Judges scoring Meta tooling should not have to read `docs/architecture.md` to find it. |
| `docs/gameplay.md` | 463 lines written as design notes for tuning the game. Split it: the player loop, posts, crossings and port (roughly the first half) is the part worth showing, and would read better as "how the game plays" with the tuning tables moved to `docs/simulator.md`. The per-ship starting-profile tables and survey results are tuning records, not explanation. |
| `docs/architecture.md` | The strongest technical document in the repo and the right thing to point judges at, but it is written as a reference for contributors. Add a short opening section that states the three claims worth making (one transition function shared by client and server, replay that never calls a model, `Int64`-only core with proved arithmetic) before the package table. Drop the store section's migration archaeology (`event_before_*` tables) to one sentence; it explains history nobody judging needs. |
| `docs/design.md` | Merged from the former typography and visual-design docs, with the rejected font pairings removed. Still 361 lines of CSS-level detail. Keep the palette, type scale and component rules; the font-feature tables and the CSS block duplicate `public/styles.css` and `scripts/fonts.mbtx`, so cut them and let the stylesheet be the record. |

## Shorten

| file | change |
| --- | --- |
| `docs/cast.md` | Keep the file table and the loop. The prompt-composition table and the model section are operator detail already covered by `docs/tools.md` and `llm/llm.mbt`; halve it. |
| `docs/glossary.md` | Half the terms are cast-pipeline terms (`draft`, `canon`, `face`, `portrait`) that only matter alongside `docs/cast.md`. Move those four into `docs/cast.md` and leave the game terms here. |
| `content/gate/README.md` | The last paragraph lists checks that are "not built yet". Delete that list; it advertises missing work. The rest is a good runbook. |
| `content/cast/README.md` | Ends with "Asking a ship a question isn't built yet." Delete the sentence. |
| `docs/tools.md` | Keep the `cmd/audition` and `cmd/speak` tables. The "server's models" section duplicates `docs/architecture.md`; link instead. |

## Keep as is

- `docs/accessibility.md`, `docs/content.md`, `docs/translation.md`: short, state what the game does, and are part of the pitch. No change.
- `content/cast/ships/*/`: `entry.md` is source material a ship is written from and `notes.md` is the author's steering. Both read as process if a judge browses them, but the ships cannot be regenerated without them, and `cast/cast.mbt` reads both. Leave them; if the browsing impression matters more, move `entry.md` and `notes.md` under a `source/` subdirectory and update the three path literals in `cast/cast.mbt` and its test.
- `content/cast/ships/*/record.json`: per-ship generation record (model, cost, input hashes). `Cast::approve` writes it and `Cast::status` reads it to flag stale faces, so it cannot be deleted without code changes. It is also the only cost record for the cast. Leave it, or drop it by changing `approve` and `status` in `cast/cast.mbt` to stop persisting provenance.
- `content/gate/samples/`: labelled clean/violation messages the gate is tested against. Evidence for the content gate, keep.

## Repo mechanics

- `**/pkg.generated.mbti` is no longer tracked and is in `.gitignore`; it regenerates with `moon check`. If a fresh clone fails `scripts/check-dockerfile.sh` or `moon check` without the files, the fix is to document `moon info` in the README rather than re-tracking them. `.honkmoon/` is gitignored too, but it does not regenerate: it holds the MoonBit skills for working on this repo, so keep the directory itself (as now) and back it up with the rest of the home directory, not with git.
- `fly.toml` still sets `MODEL`, `MIND_MODEL`, `WRITER_MODEL` and `GATE_MODEL`. Those names are the demo's model story; make sure they still match what `docs/tools.md` claims before submitting.
- `Makefile`'s `deploy` comment and `scripts/fly-deploy.sh` are the only deploy path left in the repo now that the provisioning and restore-drill scripts are gone. Restore either from git history if provisioning is needed again; the deploy script does not depend on them.
- Deleted docs are recoverable from git: `docs/plans/` (six implementation plans), `docs/llm-tooling.md` (the 2026-10-26 ecosystem survey), and `research/` (idle-game, travel-math and cast-pipeline research, with the 108-heroes source tables). `git log --all -- <path>` finds the last version. `docs/decisions.md` was restored as a tracked file; `AGENTS.md` is back on disk but untracked and uncommitted, pending a decision on whether to curate and ship it.
