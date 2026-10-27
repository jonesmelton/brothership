# spike: LLM tooling in MoonBit

What MoonBit has for a multi-stage prompt pipeline (assemble prompts from
several sources, run them on specific models, feed outputs into later
prompts), what is usable, and what we write ourselves. Spiked 2026-10-26.

## Result

A working pipeline in `llm/`, about 400 lines plus tests, built on four
dependencies:

| need | use | status |
|---|---|---|
| async, concurrency, fs, processes | `moonbitlang/async` 0.22.5 | already in the game |
| OpenAI-compatible client | `gaato/openai` 0.6.0 + `gaato/http-async` 0.5.0 | as is |
| Anthropic client, if we go direct | `gaato/anthropic` 0.12.0 | as is; small patch for cached system blocks |
| prompt templates | `bobzhang/minijinja` 0.1.1 | as is |
| sha256 for cache keys | `moonbitlang/x/crypto` | already in the game |

We write the rest ourselves: the call type, the reply cache, the
concurrency limit, the pipeline stages and the output checks. Nothing in the
ecosystem gives a usable shape for these, and each one is small.

`spike/llm/cmd/cast` ran layers 1 and 2 of
[the cast pipeline](../research/liveship-cast-pipeline.md) live on hyper
(`deepseek-v4.1-flash-1017`) for two ships: 8 calls in 45 s for $0.038 total.
A rerun replays from the cache in 0.1 s. At that rate all 108 ships cost
about $2 for layers 1 and 2.

## spike/llm

| package | targets | does |
|---|---|---|
| `llm` | js, native | `Call` (model, system blocks, user, params) and its sha256 `key`; `Reply` with usage and cost; `Backend`, an async function value; `Backend::limited(n)` (semaphore); `Backend::openai_compatible` (gaato) |
| `cache` | native | `cached(backend, dir~, mode~)`: `<dir>/<key>.json` per call, written atomically. `Live` calls through on a miss; `Replay` raises `Miss`, for tests and offline reruns |
| `prompt` | js, native | minijinja with strict undefined, trim/lstrip blocks and kept trailing newline; errors carry the source excerpt |
| `pipeline` | js, native | character, then three sheets concurrently in a task group; `clean` strips fences and file-name lines; `check` runs the cheap checks from the pipeline doc |
| `cmd/cast` | native | reads `prompts/` and `entries/`, writes `out/<pennant>/*.md` |

Backends compose: `cached(hyper.limited(6), dir="cache")` puts the cache
outside the limit, so cache hits don't wait for a slot. The cache gives both
resume after a failure and deterministic tests, so we don't need a separate
record/replay library.

```sh
cd spike/llm
moon test --target native   # 13 tests; js runs 10 (cache is native-only)
moon run cmd/cast           # live; key from ~/.config/brothership/hyper.key
moon run cmd/cast -- replay # cache only
```

## Inventory

From the local mooncakes index, 2026-10-26. Scratch modules for each
evaluation are in `eval/`.

### Provider clients

| package | verdict | why |
|---|---|---|
| `gaato/openai`, `gaato/anthropic` (+ `gaato/http`, `http-async`, `sdk-runtime`) | **use** | Typed request and response layers generated from the official API specs, with a hand-written facade. Builds on js and native. Retries obey `Retry-After` and handle 429 and 529. Streaming, tools, thinking. Anthropic has `cache_control` and structured output. The raw JSON is kept on responses, so provider extensions such as `reasoning_content` and `usage.cost` survive. |
| `QuietlyChan/moonai` | borrow ideas | A port of the Vercel AI SDK, 121k lines, with an agent loop and `generate_object`. Native only, and fails to build on async 0.22 without `patches/QuietlyChan-moonai-0.1.0-async-0.22.patch`. Too big to own for what we use. |
| `marianoguerra/llm` | skip | Clean IR and provider registry, builds on js. No streaming, retries, timeouts or structured output. |
| `mizchi/llm` and everything on it (`weopqrst/agent`, `totto2727/workgraph-llm`, `mooncassette-llm`) | skip | Native HTTP is a blocking `popen("curl …")` with the API key in argv. That stalls the event loop, so no concurrency. Its transitive deps also don't resolve on the current toolchain (`moon.mod.json`). |
| `DC-Z-lab/moonllm`, `trkbt10/llm_interop` | skip | Deps don't resolve on the current toolchain, or they pin old async. |

Neither gaato client has a batch API (Anthropic Message Batches or OpenAI
Batch). If we move to Anthropic and want the 50% batch discount, that is about
100 lines on `@runtime.Client::send`.

### Templates

| package | verdict | why |
|---|---|---|
| `bobzhang/minijinja` | **use** | Faithful port; its own 264 tests pass on native and js. Include, extends, macros, whitespace control, strict undefined with line numbers. |
| `ZSeanYves/moonjinja` | skip | Renders correctly, but strict errors have no variable or location, and it ships no tests. |
| `Lyllyl789/mustache` | skip | Spec tests pass, but missing variables render empty, `{{x}}` HTML-escapes markdown, and errors have no lines. |
| `uiwcvb/moonprompt`, `justjavac/template`, `lin2077-zeming/template` | skip | No includes; or precompiled into code, which rules out designer-edited files. |

A template engine earns its place because prompts are files a designer edits,
with includes and conditionals the designer owns. With `Strict`, a misspelled
field is an error with a location instead of a silently empty section.

### Orchestration, replay, agents

| package | verdict | why |
|---|---|---|
| `moonbitlang/async` | **use** | `with_task_group`, `spawn`, `Task::wait`, `@semaphore.Semaphore`, `retry(ExponentialDelay(..))`, `with_timeout`, `@process.spawn`. Covers everything orchestration needs. |
| `weopqrst/mooncassette` | borrow ideas | Good record/replay with secret redaction and drift diffs, but its `Transport` is synchronous. Our content-addressed cache does the same job. |
| `totto2727/agent-cli-sdk` | borrow | About 130 lines to drive a JSONL agent CLI over stdin and stdout; fits `claude -p --output-format stream-json`. Vendored on async 0.22 in `eval/orch/cli`, where 2 cancellation tests fail. |
| `totto2727/workgraph-core`, `moon-agent-graph`, `poipoiiii/agent-runtime` | skip | Workgraph runs nodes one at a time with no checkpoints; `moon-agent-graph` has unresolvable deps; agent-runtime is an app, not a library. |
| `colmugx/json-schema` | use if needed | For validating structured output. `mizchi/jsonschema` has TODOs where checks belong. |
| MCP (`marianoguerra/mcp*`, `colmugx/mcp`) | not evaluated | Active and recent. Relevant only if ships call tools over MCP. |

## Runtime use in the game

The game server is native, so the same `llm`, `prompt` and `cache` packages
run there with no extra work. `llm`, `prompt` and `pipeline` also build for
js, but a browser must not hold provider keys, so in-game calls should go
through a server route rather than straight from the client.

The runtime planner and decider will want tool calls. gaato/openai has
`ToolDef`, `ToolCall` and `ChatMessage::tool`, but no loop. The loop is ours
to write (about 50 lines), and I haven't tried it against hyper.

## Gaps and risks

- **Leaks that string checks can't see.** `out/HS-242/self.md` says "Fire in a
  depot", a detail from the source story. The cheap checks only catch fixed
  phrases. A model judging each sheet against the world rules is the
  natural next stage, and the pipeline shape already supports it.
- **The cache key covers the call, not the provider.** The same model id on two
  providers would share entries. That's fine while model ids are
  provider-specific; add the provider to `Call` if that changes.
- **The cache key depends on the shape of `Call`.** Adding a field changes
  every key and invalidates the cache. Cheap at this cost, but rerunning
  everything is not free.
- **Hyper extensions.** `reasoning_content` and `usage.cost` are read from the
  raw JSON. Other providers return zero cost.
- **Untested paths.** Streaming, tool calls, the js transport over the network,
  and gaato's retry behaviour under a real 429.

## Patches

| package | patch | upstream? |
|---|---|---|
| `QuietlyChan/moonai` 0.1.0 | `patches/QuietlyChan-moonai-0.1.0-async-0.22.patch`: header maps became `Map[CaseInsensitiveString, String]` in async 0.22 | yes, if we ever use it |
| `totto2727/agent-cli-sdk` 0.2.1 | vendored on async 0.22 in `eval/orch/cli`; 2 cancellation tests fail, not fixed | after fixing |
| `gaato/anthropic` 0.12.0 | not written: let `MessageRequest` take system blocks with `cache_control` (today only the generated params do) | yes |
