# cast pipeline

Each ship's cast entry becomes a private **portrait**, and the portrait
becomes the ship's **faces**: the files the running game reads. The prompts are under `content/cast/prompts/`.

Terms used only here: a **draft** is a generated entry, portrait or face,
kept in a ship's `drafts/` with its generation record and regenerated
freely; **canon** is the approved file for a stage, beside the entry,
written only by approving a draft or by hand and never overwritten by a
run; a **portrait** is the ship's private third-person character study,
made from its entry, that every face is made from; a **face** is a
first-person file made from the portrait for one reader in the running
game (`captain.md`, `voice.md`, `voyage.md`).

| file | written by | read by | players see it |
|---|---|---|---|
| `entry.md` | model, from the source; checked and edited by the author | portrait, faces | never |
| `notes.md` | the author, optional | portrait | never |
| `portrait.md` | model, third person | faces | never |
| `captain.md` | model, first person | planner, speaker | never directly |
| `voice.md` | model, first person, spoken | planner, speaker | yes, verbatim lines |
| `voyage.md` | model, first person | decision-maker, speaker | never |

## the loop

```sh
moon run cmd/cast -- run                    # draft what each ship is missing
moon run cmd/cast -- status                 # what is canon, edited, stale
moon run cmd/cast -- approve HS-242 portrait 2
moon run cmd/cast -- run HS-242             # now drafts its faces
moon run cmd/cast -- run --replay           # cache only; a miss fails
```

`run` drafts `samples` drafts (from `cast.json`) of every stage a ship is
missing, all concurrently, and prints each draft's cost and check problems.
A ship without a canon entry gets entry drafts and waits. A ship without a
canon portrait gets portrait drafts and waits. A ship with one gets drafts
of every face it has no canon file for.

## the entry stage

A ship starts from its pennant alone. `run <pennant>` on a pennant with no
directory drafts its `entry.md` from a seed the code builds out of what
the repo already knows (its row in `pennants.tsv`, and every line naming
the pennant in other ships' canon entries) plus all 108 pennants and
epithets; everything else, the source figure's life, episodes, kinships
and star, the model writes from its knowledge of the Water Margin. The
entry prompt keeps the draft in the novel: no liveships, no setting
translation. That is what makes the author's check possible: read the
drafts, correct one against the novel, `approve <pennant> entry <sample>`,
then edit `entry.md` by hand where the model got the book wrong.

Drafts live in `ships/<pennant>/drafts/`, each with a `.json` record;
`approve` moves the chosen record into `record.json`, the ship's
generation record. Replies are cached in `.cache/llm` by a hash of the
whole call, so rerunning after a failure, or after changing one prompt,
only calls the model for calls whose inputs changed. Editing a canon
entry or portrait marks what was made from it `stale` in `status`.

## where the author steers

In order of leverage. Nothing a player writes reaches these models (see
[content.md](content.md)); players steer through game events.

1. **The entry check, and `notes.md`.** An entry draft is model memory of
   the novel, not the novel. Read it against the source before approving,
   and correct the canon file by hand after; that pass is the only place
   facts enter. `notes.md`, written before the portrait run, goes into the
   portrait prompt, ranked above the entry ("lean into its debt to the
   Wise Star", "she, not he"). Models keep the source figure's gender
   unless told otherwise; both HS-242 drafts in the first run did.
2. **Approving the portrait.** Everything downstream inherits it. Pick a
   draft, edit it by hand if needed, then approve.
3. **Faces.** Pick a draft per face and edit lines in the canon file.
   `status` shows hand edits as `edited from <n>`.
4. **Staleness.** When an entry, notes or portrait changes after a file was
   approved, `status` marks the file `stale` and names the input that changed.
   Delete the canon file to have `run` draft it again.

## prompts

`content/cast/prompts/`, rendered with minijinja in strict mode: an
undefined variable is an error that names the template and line. The
system template for each stage composes its task with `setting.md` (and,
for the portrait and faces, `world.md`); the user template carries the
canon text of the stage before it. A ship's title is its pennant, Chinese
conventional name and English epithet together, but generated ship text
uses epithets only. The templates themselves are the
record; `cast/cast.mbt` lists which file feeds which stage.

## model

Every stage runs on `meta:muse-wonder-1.0`, configurable per stage in
`cast.json`. List rates are in `llm/llm.mbt`; reply caching is under
[the loop](#the-loop).
