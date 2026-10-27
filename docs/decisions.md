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
