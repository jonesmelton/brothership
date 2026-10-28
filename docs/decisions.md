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

## 2026-10-27 · the content gate is Muse Spark 1.3
Supersedes "the content gate is gpt-oss-safeguard-20b on Groq". `llm/gate`
calls `meta:muse-spark-1.3` on Meta Model API.
Why: on the sample set it labelled every message correctly, including all
four injection attempts, where gpt-oss-safeguard-20b missed a faked end of
message and cruelty played as a joke. It also keeps every shipping model
Meta's. It takes about 2 s per check against Groq's 0.7 s, which the game
can absorb because no model call sits between input and feedback.
Revisit if: checks need to be fast enough to sit between a player's input
and its feedback, or a held-out sample set shows it missing what gpt-oss
catches.
## 2026-10-27 · one Fly machine; Litestream is the backup and the restore path
One machine and one volume, never autostopped. Litestream replicates the
sqlite log to Tigris every 30 s, and a boot with no database restores from
it, so recovery and normal boot share one path.
Why: `Store` holds the snapshot in memory and sqlite has one writer, so a
second machine would diverge.
Revisit if: deploy downtime matters (then LiteFS) or the game needs more
than one server.

## 2026-10-27 · the hull band rises only 5% above its edge
`Crossing.band` falls as soon as the hull drops below the band's edge and
rises again only at the edge plus `BAND_MARGIN`.
Why: without the gap, a ship mending at an edge drops a band, wears less at
the lower cap, climbs back over the edge, and repeats every tick, so a
forecast runs out of boundaries.
Revisit if: the cap stops depending on the hull, or wear stops depending on
the setting.

## 2026-10-27 · the ship reconsiders its ask only when something happens
What the ship asks for changes only at a phase change, a demand opening or
closing, or the hull changing band, never because crew moved.
Why: recruits follow asks. A ship asking for the emptiest post whenever a
hand moved chased its recruits from post to post every tick. Asks are also
speech, which `docs/accessibility.md` treats as scarce.
Revisit if: recruits stop following asks.

## 2026-10-27 · recruits work ship posts only
Recruits run the steady policy: demands, asks, the drive and the hull. They
never craft, so they make no works.
Why: recruits who craft deliver works that bring more recruits, and the cap
was reached by the second port.
Revisit if: recruiting gains a cost or a limit per port.

## 2026-10-27 · the deployed image tracks `latest` MoonBit, not a pinned toolchain
The Dockerfile installs MoonBit from the unversioned installer. The
installer's linux-x86_64 URL returns 403 for the local toolchain version
(`0.1.20261020`) and 200 only for `latest`.
Why: a pin that can't be downloaded is not a pin, and a rebuild today needs
the version the installer serves.
Revisit if: the installer starts serving dated builds, or a `latest` upgrade
breaks the image build without a code change.

## 2026-10-27 · time is a server event
Only the server writes `Tick(at~)`, in Unix seconds. A tick later than
`State.at` advances the voyage by the difference; an earlier or equal one
changes nothing. Clients show a local tick and never propose one.
Why: a client that can propose elapsed time can move game time, and replay
must never read the clock.
Revisit if: ticks need to be finer than a second, or tick rows become a
storage problem.

## 2026-10-27 · clients send intents, the server writes events
`Proposal` carries a crew id and an `Intent`. `Event` adds `Tick`,
`Departed`, `Docked`, `Asked` and the ship's `Refitting`, which no
client-sendable type can express.
Why: a client can't fake a server event, because its type has no
constructor for one.
Revisit if: a player action needs to write something only the server can
write today.
