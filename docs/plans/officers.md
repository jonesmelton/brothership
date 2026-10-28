# brief: officers and rank

Five US Navy ranks for a ship's officers, promotions the ship decides, and
a rank shown in full on a player detail view and abbreviated elsewhere.
This is a brief for the full plan: what exists, the questions that change
the design, a default to argue with, and implementation notes. Written
2026-10-28.

## what is wanted

| rank | full name | abbreviation | insignia |
| --- | --- | --- | --- |
| 0 | Ensign | ENS | ○ |
| 1 | Lieutenant junior grade | LTJG | ● |
| 2 | Lieutenant | LT | ●● |
| 3 | Lieutenant commander | LCDR | ●●● |
| 4 | Commander | CDR | ★ |

- No `Captain`. The ship is the authority, and the word does not appear in
  player-facing text.
- Rank is per ship. The same officer can hold different ranks on different
  ships. A crew member new to a ship starts at `ENS`; rank does not
  transfer.
- The player detail view shows the full rank. Other views show the
  abbreviation and insignia.
- The ship promotes loyal officers when the ratio of ranks among its
  officers is skewed. There are no demotions. A ship that becomes topheavy
  stays topheavy: its senior ranks outweigh its junior ones, usually
  because junior officers left.

There is no watch limit in the plan. The current four ranks do set one
(see "what exists"); the plan removes that coupling rather than adding a
fifth limit. Rank becomes standing only: it grants nothing mechanical.
What replaces the limit is argued in "what rank does" below.

## what exists

- `core/ship.mbt` has four ranks, 0 to 3, derived from regard.
  `rank_thresholds` are 0, 40, 120 and 280 hours, `rank_of` returns the
  rank, and `max_watch` gives 2, 4, 8 or 12 hours. `Record` holds regard,
  works and carry; `Ship::rank` reads the record's regard.
- `Hand.rank` is a snapshot taken when a crew member takes a post, so a
  watch limit is fixed for the crossing. The simulator uses it to choose a
  watch length.
- `Crossing::dock` adds each tally's regard to the record. It does not
  store a rank.
- Rank is not displayed. The client uses `h.rank` only to decide which
  watch lengths to offer. `words.you_sentences` says nothing about rank.
- There is no player detail view and no crew roster. The check-in has a
  "You" section; `docs/visual-design.md` lists a crew roster as not yet
  designed.
- Crew ids are opaque (`officer-<hex>` in the live game, `crew 1` in the
  simulator). `words.told` says "You" for the session's officer and "A
  hand" for anyone else. There are no display names, and no interface to
  set one.
- Recruits are a count in `Ship` in the live game. In `sim`, recruits are
  hands with the `Steady` policy. The two are not the same kind of thing.
- Today the ship model sees no officer at all: `speech` renders
  happenings with `you=""`, so every crew id becomes "A hand", and the
  readout gives only counts per post. The plan relaxes that (see "what
  the ship may see" below). `content/gate/policy.md` says ships speak at
  promotions, and `content/gate/samples/clean/promotion.md` names a
  bosun. That naming is compatible with the relaxed policy, provided the
  name is a handle, not player text.
- The shipped Fira Sans and EB Garamond subsets do not contain U+25CB,
  U+25CF or U+2605. The sources lack them too, and the Latin subset ranges
  do not include geometric shapes or miscellaneous symbols. The source
  Noto Serif TC has all three; the shipped CJK subset does not keep them.

## questions to settle now

### what the ship may see

The model may see a server-issued identifier for each officer, and
structured facts about that officer: posts held, watches stood and
broken, works finished, regard and rank. It needs that to remember who
answered, to single an officer out, and to write a promotion line that
names someone. The policy is not "the ship sees nothing about players";
it is "the ship never sees freeform text a player wrote".

Today there is no player freeform text at all. `Intent`
(`core/state.mbt`) is enums and one `Int64`, so nothing a player sends
can carry instructions, slurs or source-novel names into a prompt. Crew
ids are already public (they appear in snapshots and the log); only the
session token is secret.

A display name breaks that only if the player can write it. So:

- Each officer gets a unique handle the ship can use: stable per ship,
  unique among the ship's officers, and not player-written. The officer's
  crew id itself qualifies. A shorter call sign assigned by the server
  at joining also qualifies, provided nobody typed it.
- Officers can have display names for other players. For now there is no
  interface to change one, so any name shown is assigned, not written.
  Display names are interface text only: the ship does not get them in
  its prompt, and a ship line never contains one.
- If an interface to set a display name is ever added, the name stays out
  of prompts unless it is chosen from a closed server-side list. A
  player-typed name is a prompt-injection and moderation vector: the ship
  echoing it back to other players would bypass the gate at input time.
  Substitution of a display name into a ship line, if ever wanted, must
  happen server-side after gating, on a name validated when it was set.

The ship's handle lets the model attribute actions and return a choice
(such as whom to promote). The handle needs no player-facing form today:
the promotion's terse sentence can use "You" / "A hand" as now, while
the ship's line can refer to the officer by handle or by what they did.

### who holds a rank

The glossary defines `officer` as the crew member a player controls, and
`rank` as a crew member's public standing. The new ladder is a US Navy
officer ladder, so the two terms can diverge.

- Officers only: ranks are held by session officers. Recruits are enlisted
  crew and hold no rank. The ratio counts officers. Core cannot tell an
  officer from a recruit, so the promotion policy takes a list of officer
  ids from outside: `Store` from its `session` table, `sim` from
  `Actor::is_player`.
- Every hand: ranks are crew standing, as today. Recruits can be promoted.
  No officer list is needed, and the ratio counts hands. A recruit can
  become a lieutenant, which reads oddly with the officer ladder.

Recommendation: officers only. It matches the user-facing word, the player
detail view, and the five officer grades. The officer list is the only new
seam. If the full plan chooses every hand, say so in the plan and in
`docs/gameplay.md`.

### what the ratio counts

The ratio can mean three things.

| interpretation | what a promotion changes | fits |
| --- | --- | --- |
| rank distribution over officers | one officer's grade | "topheavy", "no demotions" |
| officer to enlisted | nothing; it is a recruiting target | no |
| officer establishment per ship | one officer's grade | a small ship |

Recommendation: a rank distribution over officers, expressed as a cap per
rank. A starting establishment for a ship of about ten officers:

| rank | cap |
| --- | --- |
| CDR | 1 |
| LCDR | 2 |
| LT | 3 |
| LTJG | 4 |
| ENS | no cap |

This is the 1:2:3:4 pyramid, and its senior ranks sum to ten. A ship with
fewer officers has open caps, not a smaller pyramid; a solo officer can
still climb. A ship that loses its junior officers can become topheavy
while every count stays under its cap. There is no demotion to rebalance
it; new crew fill the lower ranks as they join.

The numbers are tuning. Put them in one function in `ships` so
`cmd/survey` can compare them. If the plan wants a pyramid that scales with
headcount, express it as a function of the officer count and keep this cap
table as the default.

### who decides, and what loyalty means

The ship can choose promotions with a scripted policy, the way
`Temperament` chooses asks and refits today, or with a model call. A model
choice needs a structured reply (who and which rank), a fallback, a pending
state, and a prompt that lists candidates by a handle the model can
return. Candidates are handles plus structured facts, never player text
(see "what the ship may see"), so that prompt is safe to build.

Recommendation: a scripted policy in `ships` chooses, and the existing
speech path writes the line about the `Promoted` happening. This follows
the pattern in `docs/architecture.md`: the model replaces `Temperament`
later, and every model-driven choice has a scripted policy. The seam for a
model choice should be one function, not code scattered through the clock.
A personal citation is no longer blocked by anonymity; it is blocked only
from using player-written text.

Loyalty is regard. It is already weighted by the ship's authored values,
doubled for the post the ship asks for, and doubled again for an open
demand, so a ship that values craft promotes crafters and a ship that
values the drive promotes drivers. A separate loyalty score would
duplicate it. If the plan wants watches or works in the score, add them to
the eligibility function and say why.

### when a promotion lands

Recommendation: at arrival, before `Docked`. The crossing still has its
hands, so the policy can see who is aboard and what they did on this
crossing. `Crossing::dock` then writes the new rank into the record.

- A mid-crossing promotion would put a ceremony in the middle of a
  crossing and change standing while the crossing's record is still being
  earned. Avoid it.
- A promotion in port, after docking, has no hands. The ship would need the
  last crossing's roster to avoid promoting someone who left.
- One step at a time at each arrival is a natural ceremony and keeps `CDR`
  rare. Two ranks in one arrival is a different call; leave it out unless
  the plan has a reason.

### what a promotion is in the log

A server event, not an intent: `Event::Promoted(crew~, rank~)`. A client
cannot express it, as with `Asked`, `Refitting` and `Docked`.
`State::apply` forwards it to the crossing, where it is allowed only when
the crossing has arrived and the crew member is aboard. `Crossing::dock`
writes the hand's rank into the record.

`Record.rank` is `Int64?`: missing means "not yet explicit", so an old log
decodes and the rank falls back to `rank_of(regard)`. When `dock` writes
the rank, it becomes explicit. An old record is seeded on its next dock.
MoonBit's derived `FromJson` reads a missing optional field as `None`;
checked on 2026-10-28 with a struct of an `Int64?` and an `Int64`.

The `Promoted` event is also the only source of a `Promoted` happening, so
`happenings` can return it directly rather than diffing hands.

### what rank does

Today it sets the longest watch. The plan removes that. Rank grants no
authority, no destination choice, no refit choice and no mechanical cap.
`docs/gameplay.md` already says rank grants no authority; the plan makes
the same true of the clock.

Dropping the watch limit itself, in the same change:

- Delete `max_watch` and the `rank` field's watch role. `Hand.rank` no
  longer gates anything; if it survives at all it is display standing for
  the crossing, sourced from the record's explicit rank.
- `Watched` keeps its lower bound (at least an hour, so a watch is a
  commitment rather than a quarter-multiplier toggle) and loses its upper
  bound. The simulator's `Actor::watch` drops its `.min(max_watch(rank))`
  clamp and stands the absence-covering watch it computed.
- The client offers the same watch lengths to everyone. The current
  option list tops out at 12 hours; keep 12 as an interface choice, not a
  rule, or offer whole hours up to a plain UI cap. Nothing in `core`
  rejects a longer watch.

Why not keep a flat cap in `core`: a cap is an offline-progress ceiling,
and the game already lets a player be away for a whole crossing on a
standing order. A cap punishes the player who plans ahead without
preventing any abuse — a watch is broken by changing post, not by
returning, so length mostly commits the returner, not the absentee.

If the plan wants rank to unlock something, that is a separate decision.
The roster and works shelf are already out of scope.

### where rank is shown

There is no player detail view. The full plan should say which view it
means. Three possibilities, all compatible with the rank model:

- Expand the "You" section in place: a rank line with the compact form,
  plus the full rank and record in an expanded region.
- Add a separate detail view for the session's officer, reached from
  "You". The client has no router today, so this needs a routing decision.
- Leave the detail view for the roster, and show the compact form in "You"
  now.

Recommendation: the compact form in "You" now, and a detail view for the
session's officer when the roster is designed. The full rank needs a place
where it is the main text, not a label.

The full plan must also say what else the detail view shows. Regard,
works and the rank are in `Record` or `Hand`; crossings are in `Ship`. A
rank alone is a thin page.

### how the ship speaks a promotion

The ship's line is generated by the existing speaker from the `Promoted`
happening. The terse log sentence uses "You" or "A hand" and the full rank,
for now, because there is no player-facing handle yet. The ship's line may
single the officer out by handle or by what they did ("the hand who held
the hull through the breach"), under the boundary in "what the ship may
see": handles and structured facts only, never player-written text, and
never a display name.

That makes `content/gate/samples/clean/promotion.md` ("Bosun
Achterberg. You held the breach for nine hours…") aspirational in one
specific way: "Bosun Achterberg" is a name, and the ship has none to use.
The citation shape — what was done, tied to the rank — is the voice to
keep. The sample needs no update as a gate sample; it classifies register,
not name availability.

### does no captain reach the prompts

Player-facing text: yes. The top rank is `Commander`; the ship is the
authority; no interface string says "captain".

Internally, `content/cast/prompts/world.md` says "captain and hull
together", `faces/voyage.md` uses "captain" for the ship's role, and the
face file is `captain.md`. If the ban is absolute, those need a rename and
edits, plus updates to `docs/cast.md` and the cast pipeline's stage names.
If it is only the rank ladder, leave the internal names and add one line
to the speech prompt: never call yourself captain.

Recommendation: player-facing only for this feature. A prompt that primes
the model with "captain" can still leak the word into a line. If that is
unacceptable, the prompt edit is part of the plan.

## a default shape

This is a starting point, not a prescribed implementation.

1. Add the five-rank table in `core`: the thresholds used for
   eligibility, and the integer constants. Remove `max_watch` and the
   upper bound on `Watched`; keep the one-hour minimum. Put the full
   names and abbreviations in `words`, because sentences and the server
   need them.
2. Add `Record.rank : Int64?`. `Ship::rank` returns it when present and
   falls back to `rank_of(regard)` when missing. Rename `rank_of` to
   `rank_floor` or `eligible_rank` so it reads as a floor, not the rank.
3. Add `Event::Promoted(crew~, rank~)` and
   `CrossingEvent::Promoted(crew~, rank~)`. Reject it unless the crossing
   has arrived, the crew is aboard, and the rank is one step up.
4. Add a `promotions` function in `ships`: given the ship, the arrived
   crossing and the officer ids, return the promotions due. It uses regard
   plus this crossing's tally for eligibility, the cap table for the target
   rank, and one step per promoted officer. `Profile::due` applies them
   before `Docked`.
5. `Crossing::dock` writes each hand's rank into its record. A hand with
   no record gets one.
6. Add `Happening::Promoted(crew~, rank~)`, a `words.told` sentence,
   `Announce` priority, and a speech weight. The ship's line is written by
   the existing speaker.
7. Add the rank display to the client and the "You" section. Full rank in
   the detail view; abbreviation and insignia in compact labels; full rank
   in prose and accessible names.
8. Add the symbol subset or accept the fallback, and test it in both
   schemes and at large text.
9. Add tests: the rank table, the one-step rule, the no-demotion rule, the
   cap, a solo officer, a topheavy ship, old JSON without `rank`, a
   promotion row replayed, and the client's accessible name.
10. Update `docs/gameplay.md`, `docs/glossary.md` and
    `docs/visual-design.md` where the numbers or the display rule changed.
    Propose a `docs/decisions.md` entry for the rank ladder and the
    promotion rule.

## style notes

| context | form | example |
| --- | --- | --- |
| player detail view | full rank, sentence case | Lieutenant commander |
| "You" line, roster, compact label | abbreviation, then insignia | LCDR ●●● |
| prose, log sentence, ship's line | full rank, lowercase | promoted to lieutenant commander |
| screen reader | full rank, never the abbreviation | Lieutenant commander |

- The abbreviation is uppercase (`ENS`, `LTJG`, `LT`, `LCDR`, `CDR`). The
  full rank is sentence case in a label and lowercase in a sentence.
- Do not write "Lt. Cmdr." or "Lt Cdr". The game uses one form: `LCDR`.
- The insignia is `○`, `●`, `●●`, `●●●`, `★`. One mark per rank; the count
  of filled circles is the rank.
- Put the abbreviation and insignia in one nowrap span. The insignia is
  `aria-hidden`; the accessible name is the full rank, either as the
  visible text in the detail view or as visually hidden text in the compact
  form. Do not use `abbr title`; it is not reliably announced.
- The insignia repeats the abbreviation, so it is decorative for
  accessibility. It is never the only indication of rank. Set it in
  `--quiet`; the abbreviation is `--ink`.
- The detail view may show the insignia beside the full rank as a mark. If
  it does, keep it `aria-hidden`; the full rank is the text.
- No `Captain`. Do not use "captain" in any rank string, button, log
  sentence or ship line.
- A promotion in the log: "You were promoted to lieutenant commander." or
  "A hand was promoted to lieutenant commander." The ship's line is its own
  `Spoke` entry. Keep the terse sentence even if the ship's line is blocked.
- The rank line in "You" is not a sentence. Do not put `LCDR` in a prose
  sentence; use the full rank there.

## implementation notes

### core

- `core/ship.mbt`: the five-rank table, thresholds, `Record.rank`,
  `Ship::rank`. Delete `max_watch`.
- `core/crossing.mbt`: `CrossingEvent::Promoted`, `Crossing::apply`,
  `Crossing::dock`. `Watched` drops its `longest` check; `BadWatch`
  shrinks to the sub-hour case or is replaced by it. `Hand.rank` loses
  its "sets the longest watch" doc and role.
- `core/state.mbt`: `Event::Promoted`, `State::apply`, a rejection case.
- `core/story.mbt`: `Happening::Promoted`, `happenings`.
- `core/crossing_test.mbt`, `core/state_test.mbt`, `core/story_test.mbt`.

Keep rank `Int64`: the core's rank is a small integer, the thresholds and
records are integers. An enum would read better but needs a conversion at
every boundary. It is not required for the log, because `Record.rank` is
new and optional. Named constants are enough.

The simulator check-in in `sim/run.mbt` stands the watch its absence
implies, unclamped; expect survey watch and regard numbers to move, and
report that as an expected result, not a regression.

### ships

- The promotion policy and the cap table. The policy is pure and takes the
  officer ids.
- `Profile::due` calls it before `Docked`. Add the officer list to the
  signature. `Store` supplies session officers; `sim` supplies its players.
- `ships/ships_test.mbt` and `words/words_wbtest.mbt` call `due` with the
  new argument.
- `sim/run.mbt`: `Scenario::voyage` calls the policy at arrival before
  `dock`, or uses the same `Profile::due` path. The `fly` loop does not
  dock; keep the promotion in the docking path so the simulator and the
  server agree.
- `cmd/survey`: print the rank distribution and promotions per voyage. The
  existing output for actors' ranks will change; explain the differences in
  the plan's expected result.

### store

- Load the session officers into the store on open, and add new ones in
  `open_session`, so `due` has the list without a query per call. Or query
  once per `due`; at this scale either is fine.
- The `Promoted` event is written in the same transaction as `Docked` and
  the tick. A client proposal cannot carry it.
- A promotion row replays: open a store, fly to arrival, close, reopen,
  compare snapshots and story.

### words and speech

- `words`: `rank_full`, `rank_abbreviation`, the `Promoted` sentence,
  `Announce` priority.
- The promotion sentence uses the full rank, not the abbreviation.
- `speech`: add `Promoted` to `weight`. It is not urgent. The current
  speaker marks every fresh happening considered even when it writes no
  line, so a non-urgent promotion seen inside the quiet window is dropped,
  not deferred. If promotions must wait and still be spoken, change
  `Speaker::step` or `worth` to leave the promotion unconsidered; that is a
  change to the speaker, not just a weight. Give the promotion a weight
  above the arrival so it wins the step when both are fresh; at arrival the
  readout gives the model both, so one line can cover both. If the plan
  wants a separate promotion line, the speaker needs a queue.
- The speech prompt's "never single one out" rule is replaced by the
  boundary in "what the ship may see". Rewrite that line in
  `content/speech/system.md`: the ship may address or describe one officer
  by the handle it is given and by what they did, and must not invent a
  name for anyone. The prompt gains a per-officer block (handle, post,
  watches, works, regard, rank) for the officers in the readout, so the
  model can attribute happenings instead of receiving only post counts.
  This is new prompt surface; keep it structured and server-generated.

### client

- `cmd/browser/main.mbt`: the "You" section gets a rank line. The detail
  view, if added, reads `ship.records` in port and `crossing.hands` under
  way.
- `public/styles.css`: `.rank`, `.insignia`; `font-variant-emoji: text` on
  the star if the platform picks an emoji presentation; test on iOS.
- `scripts/fonts.mbtx`: the Latin subset ranges do not include the marks,
  and the sources lack them. The source Noto Serif TC has U+25CB, U+25CF
  and U+2605; the shipped CJK subset does not keep them. Add a small symbol
  subset or append the marks to the hanzi text file and reuse the CJK face.
  Check the marks at 1rem in both schemes before choosing.
- `cmd/browser/a11y_wbtest.mbt`: the compact form's accessible name is the
  full rank; the insignia is hidden.

### tests and checks

- `make check`.
- The new rank tests in `core`; the promotion policy tests in `ships`; the
  store replay test; the client string tests.
- A manual screen reader pass on the "You" line and the detail view: the
  abbreviation must not be spelled out, and the insignia must not be
  announced.
- A visual pass at 400% zoom and in forced colors: the insignia must not
  overflow, and the abbreviation must remain.

## left undefined

- The exact thresholds and caps.
- Whether the model chooses whom to promote.
- Whether ranks apply to every hand or only officers.
- The detail view's route or placement, and what else it shows.
- The ship-visible handle's form (crew id, or a server-assigned call
  sign), and its player-facing form, if any. Display names exist in
  principle but have no setting interface yet; the roster itself.
- Localization of the ranks.
- Any authority or unlock from rank.
- Whether the cast pipeline's `captain` naming changes.

## risks

- The officer set is the only new information outside the log. If the
  store's session list is wrong, a recruit can be promoted or an officer
  cannot. Test it with a session that has never joined a ship.
- Freezing rank at dock replaces automatic rank growth. A player who never
  gets a promotion stays at their rank even with high regard; the detail
  view should make the next rank's requirement visible, or progression
  will feel stuck.
- A promotion at arrival competes with the arrival line in the speaker. The
  one-line model can mention both, but the log's terse promotion sentence
  is the reliable record.
- Topheavy by attrition is intentional. Do not add a demotion to rebalance
  a topheavy ship.
- The insignia glyphs are not in the shipped fonts. A fallback changes
  metrics and may look different across platforms; test the three marks on
  iOS, Android and a desktop with the webfonts disabled.
- The speech prompt and the gate sample disagree about names, resolved
  in "what the ship may see": the ship may single an officer out by handle
  or by deed, and may not invent or use a display name. The sample's
  "Bosun Achterberg" is a name the ship does not have; the register is
  fine. If the ship-visible handle later gets a display form, that form
  is server-assigned, not player-written, before it enters any prompt.
- Removing the watch cap removes a stated reason to return. Standing
  orders already cover absence, so the check-in's pull becomes news and
  the next decision, not the expiry of a promise. Watch `cmd/survey`
  numbers for a collapse in player watch use; if players stop standing
  watches entirely, the quarter-multiplier incentive may need regard
  earned per hour stood to carry the mechanic on its own.