# gate

`policy.md` is the classifier's system prompt for ship messages to crew. It
is written from [docs/content.md](../../docs/content.md); when either changes,
check the other by hand. The model is `gpt-oss-safeguard-20b` on Groq (see
[docs/decisions.md](../../docs/decisions.md)).

`samples/clean/` and `samples/violation/` hold one message per file, labelled
by directory. Add a sample whenever the gate gets a message wrong.

Run from the repository root. The Groq key comes from `GROQ_API_KEY`, or
`~/.config/brothership/groq.key`; the Meta key from `MODEL_API_KEY`, or
`~/.config/brothership/meta-api.key`.

```sh
# check every sample; fails if any verdict disagrees with its directory
moon run cmd/gate

# check any messages, one per file
moon run cmd/gate -- path/to/message.md

# cache only; a miss fails
moon run cmd/gate -- --replay

# another model, as provider:model (groq or meta)
moon run cmd/gate -- --model meta:muse-spark-1.3-contributor
```

Each line of output is the file, how long the call took (or `cached`),
`clean` or `violation`, and the quote the model gave as evidence. A sample the gate got wrong starts with `WRONG`.
Replies are cached in `.cache/llm` by a hash of the whole call, so editing
`policy.md` makes every sample call the model again, and an unchanged rerun
is free. To see why the model decided as it did, read `reply.reasoning` in
the cache entry for that call.

Not built yet: the cheap checks (length, conventional names from
`pennants.tsv`), the one rewrite after a block, logging verdicts to the event
log, and wiring the gate into anything that shows text to players.
