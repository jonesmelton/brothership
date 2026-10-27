# LLM tooling

What MoonBit has for multi-stage prompt pipelines, what we use, and what we
wrote ourselves. Surveyed 2026-10-26 from the local mooncakes index. The
scratch modules for each evaluation, and the moonai patch below, are in
commit `bca5228` (`spike/eval`, `spike/patches`) and were removed after.

## What we use

| need | package |
|---|---|
| async, concurrency, fs, processes | `moonbitlang/async` |
| OpenAI-compatible client | `gaato/openai` + `gaato/http-async` + `gaato/sdk-runtime` |
| prompt templates | `bobzhang/minijinja` |
| sha256 for cache keys | `moonbitlang/x/crypto` |

All models are Meta's. Curated writing (the cast pipeline) uses Muse Wonder
(`meta:muse-wonder-1.0`) on Meta Model API (`https://api.meta.ai/v1`), keyed
by `MODEL_API_KEY`. Runtime decisions and live ship dialogue are not built
yet; when they land they will use a Muse Spark model on the same API, or
Meta open weights (Muse Spark Open, Llama) served through an
OpenAI-compatible endpoint. Non-Meta models are for tests and spikes only
(the survey below is one), not for anything that ships.

We wrote the rest: `llm` (calls, backends, routing, limits, retries), `llm/cache`
(content-addressed replies), `llm/prompt` (minijinja set up for markdown) and
`cast` (the pipeline; see [cast.md](cast.md)). Nothing in the ecosystem fit
these, and each is small.

## Inventory

### Provider clients

| package | verdict | why |
|---|---|---|
| `gaato/openai` (+ `gaato/http-async`, `sdk-runtime`) | **use** | Typed request and response layers generated from the official API specs, with a hand-written facade. Builds on js and native. Retries obey `Retry-After` and handle 429 and 529. Streaming, tools, thinking. Meta Model API speaks this protocol, so this is the client for Muse Wonder and Muse Spark. The raw JSON is kept on responses, so provider extensions such as `reasoning_content` survive. |
| `QuietlyChan/moonai` | borrow ideas | A port of the Vercel AI SDK, 121k lines, with an agent loop and `generate_object`. Native only, and fails to build on async 0.22 without a 7-line patch (see below). Too big to own for what we use. |
| `marianoguerra/llm` | skip | Clean IR and provider registry, builds on js. No streaming, retries, timeouts or structured output. |
| `mizchi/llm` and everything on it (`weopqrst/agent`, `totto2727/workgraph-llm`, `mooncassette-llm`) | skip | Native HTTP is a blocking `popen("curl …")` with the API key in argv. That stalls the event loop, so no concurrency. Its transitive deps also don't resolve on the current toolchain (`moon.mod.json`). |
| `DC-Z-lab/moonllm`, `trkbt10/llm_interop` | skip | Deps don't resolve on the current toolchain, or they pin old async. |

The gaato client has no batch API. Meta Model API lists no batch tier
either, so offline pipelines pay list rates per call; the reply cache is
what keeps reruns cheap.

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
| `totto2727/agent-cli-sdk` | borrow | About 130 lines to drive a JSONL agent CLI over stdin and stdout. Vendored on async 0.22 during the survey, where 2 cancellation tests failed. |
| `totto2727/workgraph-core`, `moon-agent-graph`, `poipoiiii/agent-runtime` | skip | Workgraph runs nodes one at a time with no checkpoints; `moon-agent-graph` has unresolvable deps; agent-runtime is an app, not a library. |
| `colmugx/json-schema` | use if needed | For validating structured output. `mizchi/jsonschema` has TODOs where checks belong. |
| MCP (`marianoguerra/mcp*`, `colmugx/mcp`) | not evaluated | Active and recent. Relevant only if ships call tools over MCP. |

## Runtime use in the game

The game server is native, so `llm`, `llm/prompt` and `llm/cache` run there as
they are. `llm` and `llm/prompt` also build for js, but a browser must not hold
provider keys, so in-game calls go through a server route.

The runtime planner and decider will want tool calls. `gaato/openai` has
`ToolDef`, `ToolCall` and `ChatMessage::tool`, but no loop; the loop is ours to
write (about 50 lines) and is untested against Meta Model API.

## Gaps and risks

- **Cost is computed, not reported.** Meta Model API returns token counts
  but no price, so `Usage::cost_usd` comes from the list-rate table in
  `llm/llm.mbt` (`rate_of`). Contributor-tier and discounted rates are not
  distinguished beyond the model id, and an unlisted model reports zero.
- **The cache key depends on the shape of `Call`.** Adding a field changes
  every key, so the next run calls the model for everything again.
- **Untested paths.** Streaming, tool calls, the js transport over the network,
  retries under a real 429, and any live call to Meta Model API: no key has
  been configured yet, so Muse Wonder output quality on the cast prompts is
  unverified.

## Patches

| package | patch | upstream? |
|---|---|---|
| `QuietlyChan/moonai` 0.1.0 | `spike/patches/` in `bca5228`: header maps became `Map[CaseInsensitiveString, String]` in async 0.22 | yes, if we ever use it |
| `totto2727/agent-cli-sdk` 0.2.1 | vendored on async 0.22 in `spike/eval/orch/cli` in `bca5228`; 2 cancellation tests fail, not fixed | after fixing |
