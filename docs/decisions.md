# decisions

Why things are the way they are. Append-only, newest at the bottom. Reverse a
decision by adding an entry that supersedes it; don't edit old entries.

Write an entry only for calls that are hard to reverse or easy to undo by
accident. Format: date and title, the decision, `Why:`, `Revisit if:`.

## 2026-10-26 · game state is an event stream, rendering is downstream
Screen reader, text and visual output all render from one structured event log.
Why: a11y can't be retrofitted onto a UI-first state model.
Revisit if: event volume makes announcement throttling intractable.

## 2026-10-26 · client and server share one transition function; client sends proposals one at a time
`core` (js+native) owns `State::apply`. The client predicts with it; the server
validates and commits with it. Proposals go one at a time; every receipt
carries the authoritative snapshot.
Why: settle is only correct if each receipt's snapshot contains exactly the
client's earlier proposals.
Revisit if: throughput needs pipelined proposals (then add per-client acked ids).

## 2026-10-26 · verified math lives in its own package
`core/math` is `proof_enabled` and holds only proof-friendly code; `core` wraps it.
Why: `moon prove` lowers whole packages and rejects `Array`, top-level `let`,
and `raise` in contracted bodies.
Revisit if: `moon prove` gains support for those.

## 2026-10-26 · all numbers in core are Int64
Every quantity in `core` is `Int64`, fixed-point where fractional; floats only in rendering.
Why: floats aren't bit-identical across js and native (libm, FMA contraction), and
ints keep `core/math` provable. 64 bits covers the hackathon's ranges.
Revisit if: a quantity is meant to grow past ~9e18 raw (then mantissa/exponent),
or Int64 emulation on js becomes a hot spot.

## 2026-10-27 · a crossing is linear stocks per phase, not a stepped simulation
Burn, coast and approach each move one `Int64` stock at a rate that changes
only at events in the log. Each route's plan (target η, coast distance) is
computed offline in floats and stored as integers; the renderer computes γ
and pace.
Why: stepping needs deterministic transcendental functions on js and native,
and breaks the linear time model that offline progress relies on.
Revisit if: the drive setting needs to change distance covered, not just time
taken.

## 2026-10-27 · model output enters the game only as events in the log
Ship asks, proposals and work descriptions are written to the log; replay
never calls a model. Every model-driven choice has a scripted policy, used by
the harness and as the fallback when a call fails.
Why: replay must be deterministic, and the harness can't afford model calls.
Revisit if: a feature needs model output recomputed when the game runs
differently.

## 2026-10-27 · ships are named by epithet in English and conventional name in Chinese
Every ship has both: `EF-147 The Tigress` in English, 顧大嫂 in Chinese
(`conventional_name` in `pennants.tsv`, Traditional). The star is metadata.
Generated ship text uses epithets only, in any language.
Why: the epithet already identifies the source figure uniquely to a Chinese
reader, so hiding behind it bought no secrecy, only a second convention to learn.
Revisit if: the Chinese conventional names begin leaking source plot into
generated text or player expectations in a way the epithet alone did not.

## 2026-10-27 · the content gate is gpt-oss-safeguard-20b on Groq
Model text shown to players passes `llm/gate` against `content/gate/policy.md`
before it's shown. The classifier is OpenAI's open-weight safeguard model
served by Groq, not a Meta model.
Why: it follows a written policy and returns a verdict with evidence, it's
cheap, and Groq runs it in about a second.
Revisit if: a Meta model follows the policy as well, or Groq withdraws the model.
