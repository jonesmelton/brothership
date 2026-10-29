# visual design

How the game looks, concretely enough to build from. Fonts and their features are in [typography](typography.md); the rules every screen obeys are in [accessibility](accessibility.md). This doc covers the rest: palette, type scale, layout and components. `public/styles.css` implements it.

## direction

The screen is a ship's papers: a registry entry and a log, typeset. The design is done with type, rules and space. It has no panels, glows, gradients, shadows, textures, rounded cards, icons or animated readouts, because those are the science-fiction interface trope the typography already refuses. The only graphics are the voyage track, the progress bars and the reckoning's two drawings, and each repeats a sentence or a table (see [the voyage track](#the-voyage-track), [bars](#bars) and [reckoning](#reckoning)). The reckoning's figures change in place every second, set as an almanac's table, not a readout: no counter rolls, nothing glows, and nothing moves but the digits.

Two voices, as in [typography](typography.md): the book (EB Garamond) for names, headings and the ship's own words; the system (Fira Sans) for telemetry sentences, labels, controls and figures.

## palette

Two schemes, chosen by `prefers-color-scheme`: **paper** in light mode, **night watch** in dark mode. There is no in-game toggle yet; the system setting is the player's choice.

| token | paper | night watch | use |
| --- | --- | --- | --- |
| `--paper` | `#f0e7d5` | `#0f1513` | page background |
| `--ink` | `#1b1914` | `#e9e0cf` | text, pressed controls |
| `--quiet` | `#6b6254` | `#8f9b92` | labels, secondary text, control borders |
| `--rule` | `#c9bca4` | `#2b3630` | hairlines between sections; decorative only |
| `--accent` | `#7e2e22` | `#c6a15b` | the masthead rule, the fill of the track and bars, the new-entry marker, focus |

Contrast against `--paper` (WCAG 2.x):

| token | paper | night watch | passes |
| --- | --- | --- | --- |
| `--ink` | 14.3 | 14.1 | AAA text |
| `--quiet` | 4.9 | 6.4 | AA text, 3:1 for control borders |
| `--accent` | 7.4 | 7.6 | AAA text, focus ring |
| `--rule` | 1.5 | 1.5 | nothing; never the only edge of a control |

Rules:

- Text is `--ink` or `--quiet`, never `--rule`. Accent text is allowed but unused so far.
- Every control has a `--quiet` or `--ink` edge, so it meets the 3:1 non-text contrast without relying on `--rule`.
- Color never carries information alone. The pressed control is filled and heavier as well as inverted; the current phase on the track is also named in the sentence above it.
- Forced colors (Windows high contrast) get system colors: controls use `ButtonText` borders and `Highlight` for pressed and focus.

## type scale

Sizes are in `rem`, so the whole page follows the system text size. The root stays at the browser default (16px); on iOS it asks for `-apple-system-body` so Dynamic Type applies (see `public/styles.css`).

| role | face | size / leading | details |
| --- | --- | --- | --- |
| epithet in the masthead | EB Garamond 400 | 2.25rem / 1.05, 2.75rem from 40rem wide | `text-wrap: balance` |
| conventional name in the masthead | Noto Serif TC 400 | 0.8em of the epithet | `lang="zh-Hant"`, nowrap |
| pennant | Fira Sans 500 | 1rem | tracked 0.08em, `tabular-nums lining-nums slashed-zero` |
| section heading (`h2`) | EB Garamond 500 | 1.25rem / 1.2 | `all-small-caps`, tracked 0.05em |
| sentence (`p`, `li`) | Fira Sans 400 | 1rem / 1.5 | proportional lining figures |
| ship's voice | EB Garamond 400 | 1.1875rem / 1.4 | accent rule at the left |
| label, legend | Fira Sans 500 | 1rem | `all-small-caps`, tracked 0.06em, `--quiet` |
| voyage track label | Fira Sans 500 | 0.875rem | `all-small-caps`, tracked 0.06em, `--quiet`; `aria-hidden` and repeats a sentence |
| control | Fira Sans 400 | 1rem | pressed 600 |
| conventional name in a control | Noto Serif TC 500 | 0.95em | Medium at text sizes, per [typography](typography.md) |
| figures in a table | Fira Sans 400 | 0.9375rem | `tabular-nums lining-nums slashed-zero` |

Small caps are always `all-small-caps` from the font (`smcp`, `c2sc`), with `font-synthesis: none`. Labels stay at 1rem because small caps already read about a third smaller.

## layout

- One column at every width, `max-width: 36rem`, centered, with `1rem` side padding (`1.5rem` from 40rem wide). Desktop gets the phone layout with more margin, not a second layout.
- Sections are separated by a `--rule` hairline and `2rem` of space, not boxes.
- The game has three pages, You, Voyage and Ship, each with its own log, reached from the [bar of pages](#bar-of-pages). The masthead is on all of them. A page opens with its `h2`, which takes focus when the page changes; its sections are `h3`.
- The vertical order of each page is fixed and never changes with state. Every page opens, under the masthead, with [the ship says](#the-ship-says), then its own `h2`. You: rank, since you were here, your post, choices, log. Voyage: where the ship is, demands, the instruments and reckoning (collapsed), while you were away, log. Ship: the ship, while you were away, log, read aloud, other ships. A section with nothing to say says so in a sentence rather than disappearing.
- The bar of pages is the only fixed element, and only on viewports at least 34em tall (see below). Otherwise the page is a plain scroll, and at 400% zoom it is.

## components

### masthead

The ship's title, `EF-147 顧大嫂 The Tigress`, as the page's `h1`, under a 3px `--accent` rule.

```html
<header class="masthead">
  <h1>
    <span class="pennant">EF-147</span>
    <span class="han" lang="zh-Hant" aria-hidden="true">顧大嫂</span>
    <span class="epithet">The Tigress</span>
  </h1>
</header>
```

The pennant sits on its own line above; the conventional name and the epithet share a baseline and wrap together. The accessible name is `EF-147 The Tigress`, since the surrounding text is English (see [translation](translation.md)). A ship with no title (the plain ship of the simulator) shows its name as the epithet.

### bar of pages

`<nav aria-label="Pages">` at the bottom with three links, `#you`, `#voyage` and `#ship`, each at least 2.75rem tall with a `--quiet` edge. The current page has `aria-current="page"`, an `--ink` edge, weight 600 and a 4px `--ink` rule under it, so it is not marked by color. A link's accessible name carries the count of entries new on that page: "Voyage" or "Voyage, 2 new". The figure beside the name, in a small box, is `aria-hidden` and for the eye only.

The bar is `position: fixed` at the bottom edge only under `(min-height: 34em)`, with matching padding under the page. On a shorter viewport, or at large zoom, it sits in the flow at the end of the page, so it never eats the space that is left for reading.

### section

`<section>` with an `h2` and sentences. Sentences are one per `p`, front-loaded, written in `words/words.mbt` before any layout. "While you were away" is a `ul` whose markers are `--quiet`; keep the default markers so Safari keeps the list semantics.

### rank

The You page opens with the officer's rank in full, a `p class="rank"` in Fira Sans 600: `Lieutenant commander ●●●`. The insignia is a mark beside the title, in Noto Serif CJK TC at `--quiet`, and is `aria-hidden`, so a screen reader hears only the rank. Its glyphs ship in the CJK subset: `○`, `●`, `●●`, `●●●` and `★` for ensign through commander. Built by `rank_line` in `cmd/browser/pages.mbt`.

The compact form, for a label beside a crew member, is the abbreviation and insignia for the eye, with the full rank in a visually hidden span, as in `LCDR ●●●` with `Lieutenant commander` hidden. Both the abbreviation and the insignia are `aria-hidden`. Built by `rank_compact` in `cmd/browser/pages.mbt`; no page uses it until a crew roster exists.

### ship's voice

What the ship itself says, as opposed to telemetry about it: a gated line. A `p class="voice"` in EB Garamond with a 2px `--accent` rule at its left. In the log it is set at the size above; on the stage it is 1.75rem with a 3px rule. Model text appears here only once it has passed the gate (see "model latency" in [architecture](architecture.md)).

### the ship says

An `h2` section under the masthead of every page, before the page's own `h2`, with no rule above it and a fixed position. In order: the ship's latest line as ship's voice, the ship's current ask as a sentence ("The ship asks for hands on the drive."), and, while a line is being written or a choice weighed, the pending sentence in `--quiet` italic Garamond. With no line yet it says "The Tigress has not spoken yet." instead of disappearing. It is not a live region: a line is announced when it lands, by the announcement regions. The log still lists every line.

### bars

A groove in `--rule` with an `--accent` fill, as in the track, under a small-caps `--quiet` label, for work toward the next work, regard toward the next promotion, each open demand and a refit under way. `aria-hidden`, shown beside the sentence it repeats, and given no numbers of its own. It updates in place with each tick; nothing animates. Built by `bar` and `measure` in `cmd/browser/bars.mbt`.

### the voyage track

Three stretches, burn, coast and approach, each as wide as its expected duration at the current setting and filled by the share of that phase's stock already spent. The current phase's label is `--ink` and bold, the others `--quiet`; the fill is `--accent` on a `--rule` groove. It sits under "Where the ship is" while underway and is absent in port.

It is `aria-hidden` and adds nothing the sentences don't say: the phase sentence names the phase, the arrival sentence gives the time. Its widths are a forecast that moves with the drive setting, so it must not grow labels with times or percentages. That would make it a second, more precise forecast than the coarsened one in the sentence. Computed by `stretches` in `cmd/browser/track.mbt`.

The track is a container query context. Below 13em wide, which is a narrow phone or any page at large text, only the current phase keeps its label; the others are hidden rather than allowed to collide. The threshold comes from the widest label, `approach`, which needs about 4.3em in a third of the track. Stretches may be narrower than their labels, and the current label overflows to the right but is clipped by the track.

### log

The ship's story, newest first, the latest 20 entries: one `li` per happening, its sentence, then how long ago in `--quiet` at 0.875rem. A ship's line in the log is set as the ship's voice. Each page's log holds only its own happenings (`@words.page_of`). An entry newer than the last visit has a 4px `--accent` rule at its left; the away list says the same in words, so the rule is never the only signal. The list has no markers, so it carries `role="list"`, which Safari otherwise drops. The pending sentence ("finding words", "weighing a choice") is on the stage, not in the log.

On the Ship page, a choice group sets what is read aloud as it happens: everything, urgent only, or nothing.

### announcements

Two visually hidden live regions, polite and assertive, are rendered from the first frame and outside `main`, so screen readers watch them before anything is said. New happenings go to them by priority (`@words.priority`); at most three sentences, then how many more wait in the log.

### choices

What the last choice changed is a `p` under the You choices, in weight 500, and also goes to the polite live region.

Each choice group is a `fieldset` whose `legend` is a label. Controls are native `button`s:

- at least 2.75rem tall, 0.5rem apart, wrapping in rows;
- `1px` `--quiet` border, `2px` radius, `--paper` fill;
- pressed (`aria-pressed="true"`): `--ink` fill, `--paper` text, weight 600;
- hover: `--ink` border; focus: 3px `--accent` outline, offset 2px.

The three post buttons carry a second line, `span.effect-note` at 0.875rem in `--quiet`, naming what taking that post would change, as `@words.post_effect` computes by applying the post to a copy of the crossing: "arrive about 2 hours sooner" for the drive, "hull stops wearing" for the hull, "banks work for your craft" for a craft. A visually hidden comma precedes it in the button's accessible name. The post already held shows none.

### ship register

The ship list ("Choose a ship", "Other ships") is the same buttons, each carrying the ship's title on one line: pennant, conventional name (Medium, `aria-hidden`), epithet. The accessible name is the English title, as in the masthead.

### reckoning

"Where the ship is" opens with the readout, a `p class="readout"` in the order of a shipping forecast: phase, arrival, hull, drive ("Burn. Occitan in about 12 hours. Hull 97%. Drive 58%, 1 of 5 hands."). The voyage track follows, then the sentences the readout leaves out. Demands come next.

The crossing as the worlds see it follows the demands, in a native `details` that is collapsed by default, its `summary` "Instruments and reckoning". The summary is at least 2.75rem tall. Built in `cmd/browser/reckoning.mbt` from `@ships.reckon` and `@words.reckoning_rows`; the physics and units follow research/liveship-travel-math.md, section 11.

Underway, in this order:

1. **Two clocks.** The crossing's rapidity over hours aboard, drawn linearly: a ramp, a plateau, a ramp down, so it is the crossing's profile. Under it a second axis, years at the worlds, and dotted lines carry each turn down to where it falls in those years, with an `--ink` line for the ship. The burns, a fifth of the hours aboard, are a sliver of the years. The aboard axis is sized as the track is, by each phase's hours at the current setting, so it moves with the drive. Flown is a 2px `--accent` line, still to fly a dashed 1px `--quiet` one; hairlines stay hairlines at any width (`vector-effect: non-scaling-stroke`). Each axis has a small-caps label and its length, in tabular figures.
2. **The crossing**, a table: time aboard, time at the worlds, light-years run and to go, and how far the light of departure leads the ship.
3. **Instruments**, a table: γ, η, pace, acceleration, how fast light outruns the ship, the Doppler factor ahead and behind, green light ahead as photon energy, how close to the bow aberration crowds half the sky, and the energy each atom ahead strikes with. Absent once arrived.
4. **The map**: the four worlds in their plane, every lane between them as a `--rule` hairline, the leg flown in `--accent` and the rest dashed, the ship as an `--accent` dot, and the Sun as a hollow `--quiet` one. Names are HTML over the drawing, above each point, so they follow the text size; each star's name is under its world's in `--quiet`.

In port, the map with the next leg dashed, then **Next leg**: from, to, distance, years at the worlds and the hours aboard it can take.

Tables are `table.figures`: a small-caps `--quiet` caption, a `th scope="row"` label at the start and its figure at the end in `tabular-nums lining-nums slashed-zero`, rows divided by `--rule` hairlines. They are what a screen reader reads; both drawings are `aria-hidden` and add nothing the tables and sentences don't say. The sentences in "Where the ship is" carry the same facts coarsened and don't tick; the tables' figures tick, as the client's clock moves every second, and are not live regions, so nothing is announced.

## not yet designed

- A works shelf and a crew roster. Both will be tables like the reckoning's, with tabular lining figures.
- An in-game scheme toggle, if players ask for one.

## Related

- [typography](typography.md): faces, features, hanzi setting, font loading.
- [accessibility](accessibility.md): the rules this design is subordinate to.
- [translation](translation.md): titles and accessible names.
