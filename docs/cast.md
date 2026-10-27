# cast pipeline

Each ship's cast entry becomes a private **portrait**, and the portrait
becomes the ship's **faces**: the files the running game reads. This is a
simpler shape than the pipeline in `research/liveship-cast-pipeline.md`,
and keeps its prompts and its reasons for them.

| file | written by | read by | players see it |
|---|---|---|---|
| `entry.md` | the author, from the source | portrait, faces | never |
| `notes.md` | the author, optional | portrait | never |
| `portrait.md` | model, third person | faces | never |
| `captain.md` | model, first person | planner, speaker | never directly |
| `voice.md` | model, first person, spoken | planner, speaker | yes, verbatim lines |
| `voyage.md` | model, first person | decision-maker, speaker | never |

## changes from the research pipeline

- **`self.md` and `command.md` are one face, `captain.md`.** The research
  found `self.md` "hardly at all" separated ships' decisions, and the planner
  always read the two together. `captain.md` keeps the rule that mattered: no
  conditionals, thresholds or instructions to itself.
- **`voyage.md` is a face, not a third layer.** It is made from the entry and
  portrait, in parallel with the others. The mechanics still arrive after
  the character exists, which was the reason for telling the model late. What it
  loses is `command.md` as an input, which was itself made from the portrait.
  Compare decisions on a few ships before relying on this.
- **A face is a template plus a line in `cast.json`.** Every face shares the
  preamble in `face.system.md`, so a new kind of content (register entries,
  letters to brothers) is a new face, not a new layer.

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
A ship without a canon portrait gets portrait drafts and waits. A ship with
one gets drafts of every face it has no canon file for.

Drafts live in `ships/<pennant>/drafts/` as `<stage>.<n>.md`, each with a
`.json` record of model, settings, input hashes, usage and the raw response.
They are rewritten freely. Canon files sit beside `entry.md` and are written
only by `approve`, or by hand. `approve` also moves the draft's record into
`record.json`. That file is the ship's generation record, so you can tell which
model wrote what.

Replies are cached in `.cache/llm` by a hash of the whole call. Rerunning
after a failure, or after changing one prompt, only calls the model for calls
whose inputs changed. Faces read the canon portrait, so editing it changes
every face's key and the next `run` drafts new faces from it.

## where the author steers

In order of leverage. Nothing a player writes reaches these models (see
[content.md](content.md)); players steer through game events.

1. **`entry.md` and `notes.md`, before anything is generated.** The notes go
   into the portrait prompt, ranked above the entry ("lean into its debt to
   the Wise Star", "she, not he"). Models keep the source figure's gender
   unless told otherwise; both HS-242 drafts in the first run did.
2. **Approving the portrait.** Everything downstream inherits it. Pick a
   draft, edit it by hand if needed, then approve.
3. **Faces.** Pick a draft per face and edit lines in the canon file.
   `status` shows hand edits as `edited from <n>`.
4. **Staleness.** When an entry, notes or portrait changes after a file was
   approved, `status` marks the file `stale` and names the input that changed.
   Delete the canon file to have `run` draft it again.

Not built yet: a judge stage to rank drafts and screen against
[content.md](content.md) (the cheap checks only catch fixed phrases), promoting
interview answers into the portrait, a dry run that counts cache misses
before spending, and world events answered by every ship's faces at runtime.

## prompts

`content/cast/prompts/`, rendered with minijinja in strict mode: an undefined
variable is an error that names the template and line.

| template | renders |
|---|---|
| `portrait.system.md` | portrait task, then `setting.md`, then `world.md` |
| `portrait.user.md` | `entry`, and `notes` if any |
| `face.system.md` | the shared face preamble, `faces/<face>.md`, setting, world rules |
| `face.user.md` | `entry` and `portrait` |

The setting, world rules, portrait task, face preamble and `voice` task are the
research pipeline's prompts verbatim, apart from the game's name, the
portrait's mention of notes, and the naming rule: a ship's title is its
pennant, Chinese conventional name and English epithet together, but
generated ship text uses epithets only. `captain` merges the `self` and `command` tasks.
`voyage` is the crossing-role task: it says the role is fixed for the crossing
and that the readout is in words, and it takes the entry and portrait instead
of earlier files.

## model

`meta:muse-wonder-1.0` for every stage, configurable per stage. The earlier
two-ship run (2 portrait drafts and 2 drafts of each face per ship) used
49,256 input tokens and 44,832 output tokens, reasoning included. At Muse
Wonder list rates ($4 input, $20 output per million tokens) that is $1.09
for two ships, about $0.55 per ship, or $59 for all 108. Drafts made before
the switch were deleted; regenerate them with `moon run cmd/cast -- run`
once a `MODEL_API_KEY` is set.
