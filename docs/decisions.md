# decisions

Why things are the way they are. Append-only, newest at the bottom. Reverse a
decision by adding an entry that supersedes it; don't edit old entries.

Write an entry only for calls that are hard to reverse or easy to undo by
accident. Format: date and title, the decision, `Why:`, `Revisit if:`.

## 2026-10-26 · game state is an event stream, rendering is downstream
Screen reader, text and visual output all render from one structured event log.
Why: a11y can't be retrofitted onto a UI-first state model.
Revisit if: event volume makes announcement throttling intractable.
