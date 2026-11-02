# gate

`policy.md` is the classifier's system prompt for ship messages to crew. It
is written from [docs/content.md](../../docs/content.md); when either changes,
check the other by hand. The model is Muse Spark 1.3 (`meta:muse-spark-1.3`)
on Meta Model API. A check takes about 2 seconds; see "model latency" in
[docs/architecture.md](../../docs/architecture.md).

`samples/clean/` and `samples/violation/` hold one message per file, labelled
by directory. Add a sample whenever the gate gets a message wrong.

Run from the repository root. The Meta Model API key comes from
`MODEL_API_KEY`, or `~/.config/brothership/meta-api.key`.

```sh
# check every sample; fails if any verdict disagrees with its directory
moon run cmd/gate

# check any messages, one per file
moon run cmd/gate -- path/to/message.md

# cache only; a miss fails
moon run cmd/gate -- --replay
```

Each line of output is the file, how long the call took (or `cached`),
`clean` or `violation`, and the quote the model gave as evidence. A sample the gate got wrong starts with `WRONG`.
Replies are cached in `.cache/llm` by a hash of the whole call, so editing
`policy.md` makes every sample call the model again, and an unchanged rerun
is free. To see why the model decided as it did, read `reply.reasoning` in
the cache entry for that call.

The server's speakers (`speech`) gate every line they write.
