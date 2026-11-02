# design

How the game looks and is set in type. `public/styles.css` implements this, and `scripts/fonts.mbtx` fetches the faces and subsets them into `public/fonts`. The rules every screen obeys are in [accessibility](accessibility.md).


How the game looks, concretely enough to build from. Fonts and their features are in [typography](#typography); the rules every screen obeys are in [accessibility](accessibility.md). This doc covers the rest: palette, type scale, layout and components. `public/styles.css` implements it.

## direction

The screen is a ship's papers: a registry entry and a log, typeset. The design is done with type, rules and space. It has no panels, glows, gradients, shadows, textures, rounded cards, icons or animated readouts, because those are the science-fiction interface trope the typography already refuses. The only graphics are the voyage track, the progress bars and the reckoning's two drawings, and each repeats a sentence or a table (see [the voyage track](#the-voyage-track), [bars](#bars) and [reckoning](#reckoning)). The reckoning's figures change in place every second, set as an almanac's table, not a readout: no counter rolls, nothing glows, and nothing moves but the digits.

Two voices, as in [typography](#typography): the book (EB Garamond for names and headings, Newsreader for the ship's own words at text size) and the system (Fira Sans for telemetry sentences, labels, controls and figures).

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

Each starting ship's page sets `--accent` to its own colour, on the `.ship` element that wraps the page. A ship outside the cast keeps the `--accent` values above. The contrast figures are paper and night watch, in that order:

| ship | hue | `--accent` paper | `--accent` night watch | on `--paper` | on `--rule` |
| --- | --- | --- | --- | --- | --- |
| `EF-147` The Tigress | plum | `#8a2a6b` | `#e596c4` | 6.5 / 8.4 | 4.3 / 5.7 |
| `EF-287` The Flea on the Drum | verdigris | `#1f6e66` | `#6fd1c0` | 4.9 / 10.2 | 3.2 / 6.9 |
| `HS-212` The Twin-Tailed Scorpion | indigo | `#33549e` | `#9cb4f2` | 5.9 / 9.0 | 3.9 / 6.1 |

Within each scheme the three accents are at least 37 apart in CIE76 ΔE, where about 2.3 is a just-noticeable difference. The floors (4.5:1 on `--paper`, 3:1 on `--rule`) and the spacing are tested in `cmd/browser/accent_wbtest.mbt`.

Rules:

- Text is `--ink` or `--quiet`, never `--rule`. Accent text is allowed but unused so far.
- Every control has a `--quiet` or `--ink` edge, so it meets the 3:1 non-text contrast without relying on `--rule`.
- Color never carries information alone. The pressed control is filled and heavier as well as inverted; the current phase on the track is also named in the sentence above it.
- Forced colors (Windows high contrast) get system colors: controls use `ButtonText` borders and `Highlight` for pressed and focus.

## type scale

Sizes are in `rem`, so the whole page follows the system text size. The root stays at the browser default (16px); on iOS it asks for `-apple-system-body` so Dynamic Type applies (see `public/styles.css`).

| role | face | size / leading | details |
| --- | --- | --- | --- |
| epithet in the masthead | EB Garamond 400 (450 at night) | 2.25rem / 1.05, 2.75rem from 40rem wide | `text-wrap: balance`, `text-autospace: normal` |
| conventional name in the masthead | Noto Serif TC 400 | 0.8em of the epithet | `lang="zh-Hant"`, nowrap |
| pennant | Fira Sans 500 | 1rem | tracked 0.08em, `tabular-nums lining-nums slashed-zero` |
| page heading (`h2.page`) | EB Garamond 400 (450 at night) | 2rem / 1.2 | roman, no small caps, no tracking; one per page |
| section heading (`h2`) | EB Garamond 500 | 1.25rem / 1.2 | `all-small-caps`, tracked 0.05em |
| sentence (`p`, `li`) | Fira Sans 400 | 1rem / 1.5 | proportional lining figures, `text-wrap: pretty` |
| ship's voice | Newsreader 400 (450 at night) | 1.1875rem / 1.4 | optical size follows the size; accent rule at the left |
| pending sentence | Newsreader italic 400 (450 at night) | 1rem / 1.5 | `--quiet`; says the ship is finding words |
| label, legend | Fira Sans 500 | 1rem | `all-small-caps`, tracked 0.06em, `--quiet` |
| voyage track label | Fira Sans 500 | 0.875rem | `all-small-caps`, tracked 0.06em, `--quiet`; `aria-hidden` and repeats a sentence |
| control | Fira Sans 400 | 1rem | pressed 600; `text-autospace: normal` on ship titles |
| conventional name in a control | Noto Serif TC 500 | 0.95em | Medium at text sizes, per [typography](#typography) |
| figures in a table | Fira Sans 400 | 0.9375rem | `tabular-nums lining-nums slashed-zero` |

Small caps are always `all-small-caps` from the font (`smcp`, `c2sc`), with `font-synthesis: none`, and only on EB Garamond and Fira Sans. Newsreader has no small caps, so the serif text never asks for them. Labels stay at 1rem because small caps already read about a third smaller.

"(450 at night)" marks the night watch scheme, where `--weight-display` and `--weight-text` are 450 instead of 400. Light type on a dark ground reads thinner, so the serif is heavier there. The sans and the section headings keep their weights in both schemes.

## layout

- One column at every width, `max-width: 36rem`, centered, with `1rem` side padding (`1.5rem` from 40rem wide). Desktop gets the phone layout with more margin, not a second layout.
- Sections are separated by a `--rule` hairline and `2rem` of space, not boxes.
- The game has three pages, You, Voyage and Ship, each with its own log, reached from the [bar of pages](#bar-of-pages). The masthead is on all of them. A page opens with its `h2`, which takes focus when the page changes; its sections are `h3`.
- [Settings](#settings) is a separate menu, reached from a quiet link at the top end of the masthead on every page, not a fourth tab. It has no log, no stage and no voice, so the ship's pages stay the ship's papers.
- The vertical order of each page is fixed and never changes with state. Every page opens, under the masthead, with [the ship says](#the-ship-says), then its own `h2`. You: rank, since you were here, your post, choices, log. Voyage: where the ship is, demands, the fleet, the instruments and reckoning (collapsed), landfall, while you were away, log. Ship: the ship, the officers, while you were away, log, leaving. A section with nothing to say says so in a sentence rather than disappearing.
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

The compact form, for a label beside a crew member, is the abbreviation and insignia for the eye, with the full rank in a visually hidden span, as in `LCDR ●●●` with `Lieutenant commander` hidden. Both the abbreviation and the insignia are `aria-hidden`. Built by `rank_compact` in `cmd/browser/pages.mbt`; the roster uses it.

### ship's voice

What the ship itself says, as opposed to telemetry about it: a gated line. A `p class="voice"` in Newsreader with a 2px `--accent` rule at its left. In the log it is set at the size above; on the stage it is 1.75rem with a 3px rule. Model text appears here only once it has passed the gate (see "model latency" in [architecture](architecture.md)).

### the ship says

An `h2` section under the masthead of every page, before the page's own `h2`, with no rule above it and a fixed position. In order: the ship's latest line as ship's voice, followed by how long ago it was said as in the log, since an old line can ask for something the ship no longer wants; the ship's current ask as a sentence ("The ship asks for hands on the drive."), and, while a line is being written or a choice weighed, the pending sentence in `--quiet` italic Newsreader. With no line yet it says "The Tigress has not spoken yet." instead of disappearing. It is not a live region: a line is announced when it lands, by the announcement regions. The log still lists every line.

### landfall

The Voyage page's section on the newest docking, between the reckoning and "While you were away". Plain `p`s, one sentence each, in a fixed order: where the ship came in and from where, with hours aboard against years at the worlds ("Made Occitan from Kerala: 14 hours aboard, 15.7 years at the worlds."); how long ago; the roll call of promotions at the muster, in order, with "you" and "a hand" for crew ids; how many of the ship's asks were answered and how many by you; works delivered and recruits gained. With no promotions, no asks or no deliveries it says so in a sentence. Before the first docking it is one sentence saying there has been no landfall. Built by `@words.landfall_sentences` from the story alone, using the `Docked` happening's `Landing` (leg, ticks aboard, works, plan), so it needs no model call and survives a reload.

The roll call is pulled, not pushed. An arrival announces at most the arrival, your own promotion and the docking; other officers' promotions are log only (`@words.priority`). A player who missed the docking gets one sentence in "While you were away" on the Voyage page, "Landfall at Occitan. The account is under Landfall on this page.", from `@words.landfall_away`.

### bars

A groove in `--rule` with an `--accent` fill, as in the track, under a small-caps `--quiet` label, for work toward the next work, regard toward the next promotion, each open demand and a refit under way. `aria-hidden`, shown beside the sentence it repeats, and given no numbers of its own. It updates in place with each tick; nothing animates. Built by `bar` and `measure` in `cmd/browser/bars.mbt`.

### the voyage track

Three stretches, burn, coast and approach, each as wide as its expected duration at the current setting and filled by the share of that phase's stock already spent. The current phase's label is `--ink` and bold, the others `--quiet`; the fill is `--accent` on a `--rule` groove. It sits under "Where the ship is" while underway and is absent in port.

It is `aria-hidden` and adds nothing the sentences don't say: the phase sentence names the phase, the arrival sentence gives the time. Its widths are a forecast that moves with the drive setting, so it must not grow labels with times or percentages. That would make it a second, more precise forecast than the coarsened one in the sentence. Computed by `stretches` in `cmd/browser/track.mbt`.

The track is a container query context. Below 13em wide, which is a narrow phone or any page at large text, only the current phase keeps its label; the others are hidden rather than allowed to collide. The threshold comes from the widest label, `approach`, which needs about 4.3em in a third of the track. Stretches may be narrower than their labels, and the current label overflows to the right but is clipped by the track.

Under the phases, a second bar is the same crossing on the worlds' clock: the phases sized by the years they take at the worlds, so the burns are slivers. It carries the label "At the worlds" and no numbers, because the coarsened sentence above already says how long the crossing takes there and the Instruments table has the exact figures. It is `aria-hidden` like the track.

### log

The ship's story, newest first, the latest 20 entries: one `li` per happening, its sentence, then how long ago in `--quiet` at 0.875rem. A ship's line in the log is set as the ship's voice. Each page's log holds only its own happenings (`@words.page_of`). An entry newer than the last visit has a 4px `--accent` rule at its left; the away list says the same in words, so the rule is never the only signal. The list has no markers, so it carries `role="list"`, which Safari otherwise drops. The pending sentence ("finding words", "weighing a choice") is on the stage, not in the log.

Other officers are named in the log and the away list by service number; the player is "You". Announcements say "A hand" instead, because a service number read aloud is spelled out letter by letter. The ship's model never sees either: `@words.told` keeps "A hand" for it.

### settings

A menu of its own at `#settings`, reached from the masthead's "Settings" link, `a.menu`. It follows the `h1` in the source, so a screen reader reaches the title first, and is set at the top end in small caps at `--quiet`. It is left by the bar of pages or its "Back to the ship" link ("Back to the fleet" before boarding). It has the plain masthead "Settings", with no ship stage, no voice and no log. Sections: **Your service number**, the officer's public id and a sentence saying the ship knows them by it; then **Preferences**, with three choice groups in this order: what is read aloud as it happens (everything, urgent only, nothing), sounds (on, off; off by default), and type (book, legible). Each is a set of native buttons with `aria-pressed`, and each is stored in `localStorage`. Legible sets `data-face="legible"` on the root, which replaces `--font-display` and `--font-ui` with Atkinson Hyperlegible Next; the hanzi keep `--font-han`. The face has no small caps, oldstyle figures or slashed zero, so labels set in small caps appear in lowercase and figures in lining. Its font files are not preloaded and load only when chosen. The page bar is shown while the player is aboard; none of its links is current on Settings.

### announcements

New happenings are announced by priority (`@words.priority`): at most three sentences each for interrupts and announcements, then how many more wait in the log. Where the browser has `document.ariaNotify`, a batch goes through it as one string: an interrupt makes the call `high` and is placed first, and a batch with announcements only is `normal`. One string per batch matters because some screen readers speak only the most recent call. Otherwise two visually hidden live regions, polite and assertive, carry the text. They are rendered from the first frame and outside `main`, so screen readers are already watching them if `ariaNotify` is missing, and they stay empty when it is present, so nothing is spoken twice. The sentences for the player's own choices go the same way.

When sounds are on, a happening that is read aloud also plays a synthesized cue: one 180 ms tone for an announcement, a two-note figure of 280 ms for an interrupt, and a softer 220 ms tone for a ship's line. Each peaks at 0.2 gain or less. A cue is never the only signal and is not played for anything the read-aloud setting filters out. The audio context is created after a gesture.

### choices

What the last choice changed is a `p` under the You choices, in weight 500, and also goes to the polite live region.

Each choice group is a `fieldset` whose `legend` is a label. Controls are native `button`s:

- at least 2.75rem tall, 0.5rem apart, wrapping in rows;
- `1px` `--quiet` border, `2px` radius, `--paper` fill;
- pressed (`aria-pressed="true"`): `--ink` fill, `--paper` text, weight 600;
- hover: `--ink` border; focus: 3px `--accent` outline, offset 2px.

The three post buttons carry a second line, `span.effect-note` at 0.875rem in `--quiet`, naming what taking that post would change, as `@words.post_effect` computes by applying the post to a copy of the crossing: "arrive about 2 hours sooner" for the drive, "hull stops wearing" for the hull, "banks work for your craft" for a craft. A visually hidden comma precedes it in the button's accessible name. The post already held shows none.

### ship register

The ship list ("Choose a ship") is the same buttons, each carrying the ship's title on one line: pennant, conventional name (Medium, `aria-hidden`), epithet. The accessible name is the English title, as in the masthead.

### reckoning

"Where the ship is" opens with the readout, a `p class="readout"` in the order of a shipping forecast: phase, arrival, hull, drive ("Burn. Occitan in about 12 hours. Hull 97%. Drive 58%, 1 of 5 hands."). The voyage track follows, then the sentences the readout leaves out. Demands come next.

The crossing as the worlds see it follows the demands, in a native `details` that is collapsed by default, its `summary` "Instruments and reckoning". The summary is at least 2.75rem tall. Built in `cmd/browser/reckoning.mbt` from `@ships.reckon` and `@words.reckoning_rows`; the physics and units are the ones `@ships.reckon` computes.

Underway, in this order:

1. **Lorentz factor over the hours aboard.** γ on a linear scale from one at the base to the coast's peak at a dotted `--rule` line, against hours aboard sized as the track is, so it moves with the drive. Rapidity rises in step with the burn's hours, so γ = cosh η stays near one for most of the burn and climbs to the peak in its last stretch; the approach mirrors it. This is the fact the track can't show. Not plotted against distance or the worlds' years: on either the burns are about 4% of the width and the drawing is a block, which the "at the worlds" bar already says. Flown is a 2px `--accent` line, still to fly a dashed 1px `--quiet` one; the ship is an `--accent` dot, HTML over the drawing so the stretched viewBox keeps it round, on an `--ink` hairline from the base. Labels give the peak and γ now above, and the forecast hours below, in tabular figures. Hairlines stay hairlines at any width (`vector-effect: non-scaling-stroke`).
2. **The crossing**, a table: time aboard, time at the worlds, light-years run and to go, and how far the light of departure leads the ship.
3. **Instruments**, a table: γ, η, pace, acceleration, how fast light outruns the ship, the Doppler factor ahead and behind, green light ahead as photon energy, how close to the bow aberration crowds half the sky, and the energy each atom ahead strikes with. Absent once arrived.
4. **The bow sight**, under the Instruments table: the sky looking forward, as a disc with the bow at its centre, an `--accent` cross. A direction θ from the bow is drawn at a radius set by ln tan(θ/2). Aberration is tan(θ′/2) = e^−η tan(θ/2), which on that scale is a shift by −η, so a fixed field of 260 `--ink` stars, spread evenly over the sphere with a few bright ones, slides toward the bow as the ship burns and keeps its shape. The scale is fixed for the crossing: from a little behind abeam at rest to a little inside abeam at the peak. Hairline `--rule` rings mark 90°, 1°, 1′, 1″ and 0.01″ where they fall in that span, each labelled in tabular figures above the bow; the `--accent` ring is half the sky, the image of the worlds' abeam, at the reckoning's cone. The caption names the scale and gives the angle. `aria-hidden`; the Instruments row carries the figure. Rendering only, in `cmd/browser/sky.mbt`.
5. **Next leg**, in port only: from, to, distance, years at the worlds and the hours aboard it can take.

Tables are `table.figures`: a small-caps `--quiet` caption, a `th scope="row"` label at the start and its figure at the end in `tabular-nums lining-nums slashed-zero`, rows divided by `--rule` hairlines. They are what a screen reader reads; the drawings are `aria-hidden` and add nothing the tables and sentences don't say. The sentences in "Where the ship is" carry the same facts coarsened and don't tick; the tables' figures tick, as the client's clock moves every second, and are not live regions, so nothing is announced.

### the fleet

On the Voyage page, after the demands and before the instruments. One sentence per other ship, from `@words.fleet_sentence`, naming its title and where it is, and never who or how many are aboard. The star map follows: the five worlds in their plane, every lane between them as a `--rule` hairline, the leg flown in `--accent` and the rest dashed, this ship as a larger `--accent` dot, every other ship as a small hollow `--quiet` dot labelled with its pennant, and the Sun as a hollow `--quiet` one. Names are HTML over the drawing, above each point, so they follow the text size; each star's name is under its world's in `--quiet`. The drawing is `aria-hidden`; the sentences are the list.

A player aboard one ship cannot read another's snapshot or story: `GET /api/ships/:id/snapshot` and `/story` answer 403 while the session's officer is aboard a different ship. The fleet list and this map are what they may see of the rest of the fleet.

### officers

The Ship page's watch bill, after "The ship". One item per officer aboard: the service number as the name, a compact rank beside it, and "You" on the player's own row. Under it, where they stand ("On the hull, on watch for about 2 hours more."), the post they have spent the most time on this crossing ("3 hours on the hull this crossing."), and their newest action as a sentence with how long ago ("Took the hull 12 minutes ago."). In port, it says the post each officer will take at departure instead of the crossing's hours. Items are ordered with the player first, then by rank, then by service number, so the list is stable. The summary says how many officers are aboard and how many recruits fill out the crew. It is a `ul` with `role="list"`, not a table: the sentences, not columns, are the content.

## typography


EB Garamond for display, Newsreader for the ship's running text, Fira Sans for the interface and data, and Noto Serif CJK TC for the hanzi. Everything here is open-licensed, and the OpenType features were checked in the font files.

## Latin

The game has two voices: a book voice for the novel it comes from, and a system voice for a ship that runs on telemetry. Pair them. A single family can do both, but the pairing below gives the anachronism more room and avoids the wide geometric sans that science-fiction interfaces default to. Do not use Eurostile, Microgramma or Bank Gothic; that is the trope.

### EB Garamond + Newsreader + Fira Sans

| role | font | what it gives you |
| --- | --- | --- |
| display | EB Garamond | true small caps in roman and italic; tabular lining by default; oldstyle in tabular and proportional sets; wght 400 to 800 |
| running text | Newsreader | optical size axis (opsz 6 to 72) and wght 200 to 800 in roman and italic; tabular lining by default; `pnum` for proportional lining; no oldstyle, no small caps |
| UI, labels and data | Fira Sans | true small caps in roman and italic; all four figure sets; slashed zero |

EB Garamond is a Renaissance book face; Fira Sans is a humanist technical sans from the 2010s. They share a humanist skeleton, so the pairing reads as a decision rather than a collision. Use EB Garamond for the masthead epithet and the headings, where its small caps are used. The ship's own lines are running text at about 19px, so they take Newsreader, whose optical size axis is set to the size of the text by `font-optical-sizing: auto`. Use Fira Sans where the ship speaks as a system: labels, buttons, table text, warnings, and every number that must line up. Tabular lining figures in Fira Sans carry the crossing readouts; a monospace is unnecessary until code or fixed-column editing demands one.

Figure and small-caps behaviour, checked in the Google Fonts builds:

| family | default | tabular lining | tabular oldstyle | proportional oldstyle | small caps |
| --- | --- | --- | --- | --- | --- |
| EB Garamond | tabular lining | default or `tnum` | `onum` | `onum` + `pnum` | `smcp`, `c2sc` in roman and italic |
| Newsreader | tabular lining | default or `tnum` | none | none | none |
| Fira Sans | proportional lining | `tnum` | `onum` + `tnum` | `onum` | `smcp`, `c2sc` in roman and italic |

The table is the reason for the pairing. EB Garamond's default figures are already tabular, so data can use it without a switch; Newsreader's are too, and `pnum` gives it proportional lining for prose. Fira Sans gives you the full set for labels and prose in the UI. Fira Sans's tabular oldstyle is rare and useful for a table that should feel typeset rather than computed, but use lining figures for telemetry: oldstyle figures in a column of changing numbers make the digits harder to scan.

### CSS

The stack below is EB Garamond + Newsreader + Fira Sans. Change the Latin families together if you pick the Source superfamily; the feature settings stay the same.

```css
:root {
  --font-display: "EB Garamond", Georgia, serif;
  --font-text: "Newsreader", "EB Garamond", Georgia, serif;
  --font-ui: "Fira Sans", system-ui, sans-serif;
  --font-han: "Noto Serif CJK TC", "Noto Serif TC", "Songti TC", "PMingLiU", serif;
  --weight-display: 400;
  --weight-text: 400;
}

@media (prefers-color-scheme: dark) {
  :root {
    --weight-display: 450;
    --weight-text: 450;
  }
}

body {
  font-family: var(--font-ui);
  font-synthesis: none;
}

p,
.log li {
  text-wrap: pretty;
}

.masthead h1 {
  font-family: var(--font-display);
  font-weight: var(--weight-display);
  text-autospace: normal;
}

.prose {
  font-family: var(--font-text);
  font-optical-sizing: auto;
  font-weight: var(--weight-text);
  font-variant-numeric: proportional-nums;
}

.data {
  font-family: var(--font-ui);
  font-variant-numeric: tabular-nums lining-nums slashed-zero;
}

.label {
  font-family: var(--font-ui);
  font-variant-caps: all-small-caps;
  letter-spacing: 0.04em;
}

.smallcaps {
  font-family: var(--font-display);
  font-variant-caps: all-small-caps;
}

.han {
  font-family: var(--font-han);
  font-size: 0.95em;
  font-style: normal;
  font-synthesis: none;
  letter-spacing: 0;
  line-height: 1.5;
  white-space: nowrap;
}
```

`font-synthesis: none` is what keeps a missing small-cap or italic from being faked. `font-variant-caps: all-small-caps` uses `smcp` and `c2sc`; with synthesis off, a font that lacks the feature will not get a synthetic one. Newsreader has neither feature, so small caps on Newsreader text render as typed. Check `smcp` and `c2sc` in the build you ship.

Night watch (`prefers-color-scheme: dark`) raises the serif weights to 450. Light type on a dark ground looks thinner, and both EB Garamond and Newsreader have the weight range to take 450. Fira Sans ships at 400, 500 and 600 only, so the sans keeps its design weights. The page heading uses `--weight-display` too.

## Legible type

The Type setting on the Ship page replaces both Latin faces with Atkinson Hyperlegible Next (Braille Institute, OFL, variable weight 200 to 800, roman and italic), subset to the same Latin range by `scripts/fonts.mbtx`. The stylesheet sets `data-face="legible"` on the root, which redefines `--font-display` and `--font-ui`. `--font-han` is untouched, so hanzi keep Noto Serif CJK TC. The font has `tnum`, `pnum`, `case` and `frac` but no `smcp`, `c2sc`, `onum`, `lnum` or `zero`, so small-caps labels display in lowercase and figures are lining without a slashed zero. The two files, 40 KB and 44 KB, are not preloaded and download only when the choice is made.

## Chinese

The game uses Traditional Chinese (Hant) for the hanzi. Keep one script across conventional names, star names, and any other displayed hanzi; do not mix. A Simplified release is a full migration, not a per-string choice. The star names use 陰, and the cast entries use 顧大嫂, 林沖, 宋江. [`pennants.tsv`](../content/cast/pennants.tsv) once mixed scripts (13 rows written from `name_zh` instead of `name_hant`); [`scripts/pennants.mbtx`](../scripts/pennants.mbtx) now reads `name_hant` and validates that every conventional name there matches, so the file stays Traditional. A Traditional Chinese font will render a Simplified codepoint as Simplified, so no font choice fixes this; the source column does.

| face | license | use |
| --- | --- | --- |
| Noto Serif CJK TC / Noto Serif TC | OFL, no Reserved Font Name | default; safe to subset and self-host |
| Source Han Serif TW | OFL, Reserved Font Name 'Source' | same design; rename a subset before redistributing |
| Chiron Sung HK | OFL | modern TC Song derived from Source Han; more written, less printed; check its glyph forms against your chosen TC standard |
| Noto Sans CJK TC / Source Han Sans TC | OFL | if the names should read as registry type rather than book type |

Use a Song/Ming face. It is the Chinese book serif, the neutral literary choice, and it will not read as costume. A brush or seal-script face would make the names decorative. A Kai face is a legitimate text style, but next to a technical Latin face it reads as calligraphy; use it only if that is the voice you want. Do not use a Japanese font, even one with broad kanji coverage: the regional glyph forms are wrong for Chinese names, and the difference is visible in characters like 直, 骨 and 類.

The Chinese face and the Latin face do not need to share a designer; they need to share optical weight. Noto Serif CJK TC Regular can look light next to EB Garamond at small sizes. Use Medium (500) for hanzi at 14–20px, especially on a dark background, and Regular for display sizes. Check the pair at the smallest and largest size you ship.

### Setting the names

- Put `lang="zh-Hant"` on every hanzi span. It selects Traditional glyph variants and correct line breaking. Do not rely on the font name alone.
- Keep the name in one unbreakable span. Chinese names are two to four characters, and a line break inside one is wrong. `white-space: nowrap` on the name, with the surrounding line allowed to wrap.
- Do not letterspace, italicize, uppercase or synthesize a bold weight. Hanzi are full-width and already spaced; tracking them is the quickest way to make them look like decoration. Use a real weight from the family.
- Hanzi fill the em square and look larger than Latin lowercase at the same size. Start at `0.95em` beside Latin text, align baselines, and adjust to the Latin cap height. A standalone mark can use a fixed size and `line-height: 1.5`.
- Use the same ink as the Latin name. No red, seal, box, glow or outline. The science-fiction treatment belongs to the layout (a registry line, a rule, a grid), not to the hanzi.
- Keep punctuation outside the hanzi span. The names have no punctuation; a Latin gloss takes Latin punctuation.
- Set `text-autospace: normal` on the element that holds a name beside Latin text: the masthead `h1` and the ship buttons. The browser then adds the gap between hanzi and Latin, including the one between hanzi and a numeral such as `EF-147`. Keep the literal spaces that `title` in `cmd/browser/main.mbt` writes around the hanzi span. `normal` is `insert`, which adds spacing only where no space character already sits, so the gap does not double. `replace` would swap the literal spaces for the autospace width. Chrome 140, Firefox 145 and Safari 18.4 support it; older browsers ignore it and show the literal spaces alone.

### What the hanzi is attached to

Every ship has an English epithet and a Chinese conventional name, and its main title is all three identifiers together: `EF-147 顧大嫂 The Tigress` (pennant, conventional name, epithet). The Chinese conventional name is the `conventional_name` column in [`pennants.tsv`](../content/cast/pennants.tsv) (Traditional, from the `name_hant` column of the Water Margin heroes table); the English epithet is the `epithet` column. The conventional name is not a translation of the epithet (母大蟲), and it is the ship's identifier on a ship card, in a register, and anywhere else the ship is named in Chinese. The star (`地陰星`) is metadata, not a name in either language.

### Accessibility

For the full title, the accessible name is the title in the language of the surrounding text: `EF-147 The Tigress` in English, `EF-147 顧大嫂` in Chinese, with the other language's name part marked `aria-hidden="true"` if announcing both would duplicate. For a short reference, match the accessible name to the language of the surrounding text: `The Tigress` in English, `顧大嫂` in Chinese. If the hanzi is the only visible name, add a visually hidden English label. Put `lang="zh-Hant"` on the hanzi span even when it is hidden from assistive technology, so the language of the text is not ambiguous. Do not put hanzi in an `aria-label` without a language tag.

### Loading

Subset the font to the characters you ship. `scripts/fonts.mbtx` does this from the `name_hant` and `star_zh` columns; rerun it if the game shows hanzi from anywhere else. The 108 `name_hant` values and 108 `star_zh` values from the Water Margin heroes table use 251 unique characters. A subset of Noto Serif CJK TC Regular to those characters is about 85 KB as WOFF2, and the two weights the game uses about 170 KB. That is small enough to self-host and preload the weight used above the fold. Do not hotlink Google Fonts: the game should work offline, and the CSS request is a privacy leak.

Newsreader is Latin only. Its roman subset is 157 KB and its italic 178 KB as WOFF2, both variable with `wght` and `opsz`. The roman is preloaded because the ship's latest line sits above the fold; the italic loads on the first pending sentence.

Noto Serif CJK TC has no Reserved Font Name, so a subset can keep the name. Source Han Serif TW and Source Han Sans TC carry the Reserved Font Name 'Source'; rename a subset before redistributing it. Subsetting counts as a modification under the OFL.

Fallback stack: `"Noto Serif CJK TC", "Songti TC", "PMingLiU", serif`. Test with the webfont disabled; a Japanese fallback will show Japanese glyph forms.

## Related

- [translation](translation.md): ship titles and accessible names.
- [accessibility](accessibility.md): announcements and screen-reader rules.
- [cast](cast.md): the pipeline that produces ship text.
