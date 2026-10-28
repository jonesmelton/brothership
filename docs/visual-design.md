# visual design

How the game looks, concretely enough to build from. Fonts and their features are in [typography](typography.md); the rules every screen obeys are in [accessibility](accessibility.md). This doc covers the rest: palette, type scale, layout and components. `public/styles.css` implements it.

## direction

The screen is a ship's papers: a registry entry and a log, typeset. The design is done with type, rules and space. It has no panels, glows, gradients, shadows, textures, rounded cards, icons or animated readouts, because those are the science-fiction interface trope the typography already refuses. The only graphic is the voyage track, and it repeats a sentence (see [the voyage track](#the-voyage-track)).

Two voices, as in [typography](typography.md): the book (EB Garamond) for names, headings and the ship's own words; the system (Fira Sans) for telemetry sentences, labels, controls and figures.

## palette

Two schemes, chosen by `prefers-color-scheme`: **paper** in light mode, **night watch** in dark mode. There is no in-game toggle yet; the system setting is the player's choice.

| token | paper | night watch | use |
| --- | --- | --- | --- |
| `--paper` | `#f0e7d5` | `#0f1513` | page background |
| `--ink` | `#1b1914` | `#e9e0cf` | text, pressed controls |
| `--quiet` | `#6b6254` | `#8f9b92` | labels, secondary text, control borders |
| `--rule` | `#c9bca4` | `#2b3630` | hairlines between sections; decorative only |
| `--accent` | `#7e2e22` | `#c6a15b` | the masthead rule, the track's fill, focus |

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

Sizes are in `rem`, so the whole page follows the system text size. The root stays at the browser default (16px).

| role | face | size / leading | details |
| --- | --- | --- | --- |
| epithet in the masthead | EB Garamond 400 | 2.25rem / 1.05, 2.75rem from 40rem wide | `text-wrap: balance` |
| conventional name in the masthead | Noto Serif TC 400 | 0.8em of the epithet | `lang="zh-Hant"`, nowrap |
| pennant | Fira Sans 500 | 1rem | tracked 0.08em, `tabular-nums lining-nums slashed-zero` |
| section heading (`h2`) | EB Garamond 500 | 1.25rem / 1.2 | `all-small-caps`, tracked 0.05em |
| sentence (`p`, `li`) | Fira Sans 400 | 1rem / 1.5 | proportional lining figures |
| ship's voice | EB Garamond 400 | 1.1875rem / 1.4 | accent rule at the left |
| label, legend | Fira Sans 500 | 1rem | `all-small-caps`, tracked 0.06em, `--quiet` |
| control | Fira Sans 400 | 1rem | pressed 600 |
| conventional name in a control | Noto Serif TC 500 | 0.95em | Medium at text sizes, per [typography](typography.md) |
| figures in a table | Fira Sans 400 | 0.9375rem | `tabular-nums lining-nums slashed-zero` |

Small caps are always `all-small-caps` from the font (`smcp`, `c2sc`), with `font-synthesis: none`. Labels stay at 1rem because small caps already read about a third smaller.

## layout

- One column at every width, `max-width: 36rem`, centered, with `1rem` side padding (`1.5rem` from 40rem wide). Desktop gets the phone layout with more margin, not a second layout.
- Sections are separated by a `--rule` hairline and `2rem` of space, not boxes.
- The vertical order is fixed and never changes with state: masthead, where the ship is, while you were away, you, choices, log, other ships. A section with nothing to say says so in a sentence rather than disappearing.
- Nothing is fixed or sticky; at 400% zoom the page is a plain scroll.

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

### section

`<section>` with an `h2` and sentences. Sentences are one per `p`, front-loaded, written in `cmd/browser/words.mbt` before any layout. "While you were away" is a `ul` whose markers are `--quiet`; keep the default markers so Safari keeps the list semantics.

### ship's voice

What the ship itself says, as opposed to telemetry about it: today the ask ("The ship asks for hands on the drive."), later the model's own lines. A `p class="voice"` in EB Garamond with a 2px `--accent` rule at its left. Model text goes here once it has passed the gate; while it is pending, the sentence that prompted it stands alone (see "model latency" in [architecture](architecture.md)).

### the voyage track

Three stretches, burn, coast and approach, each as wide as its expected duration at the current setting and filled by the share of that phase's stock already spent. The current phase's label is `--ink` and bold, the others `--quiet`; the fill is `--accent` on a `--rule` groove. It sits under "Where the ship is" while underway and is absent in port.

It is `aria-hidden` and adds nothing the sentences don't say: the phase sentence names the phase, the arrival sentence gives the time. Its widths are a forecast that moves with the drive setting, so it must not grow labels with times or percentages. That would make it a second, more precise forecast than the coarsened one in the sentence. Computed by `stretches` in `cmd/browser/track.mbt`.

### log

The ship's story, newest first, the latest 20 entries: one `li` per happening, its sentence, then how long ago in `--quiet` at 0.875rem. A ship's line in the log is set as the ship's voice. The list has no markers, so it carries `role="list"`, which Safari otherwise drops. While a line is being written, a `--quiet` italic Garamond sentence above the list says the ship is finding words; it is not a live region, since the line itself is announced when it lands.

Under the list, a choice group sets what is read aloud as it happens: everything, urgent only, or nothing.

### announcements

Two visually hidden live regions, polite and assertive, are rendered from the first frame and outside `main`, so screen readers watch them before anything is said. New happenings go to them by priority (`@words.priority`); at most three sentences, then how many more wait in the log.

### choices

Each choice group is a `fieldset` whose `legend` is a label. Controls are native `button`s:

- at least 2.75rem tall, 0.5rem apart, wrapping in rows;
- `1px` `--quiet` border, `2px` radius, `--paper` fill;
- pressed (`aria-pressed="true"`): `--ink` fill, `--paper` text, weight 600;
- hover: `--ink` border; focus: 3px `--accent` outline, offset 2px.

### ship register

The ship list ("Choose a ship", "Other ships") is the same buttons, each carrying the ship's title on one line: pennant, conventional name (Medium, `aria-hidden`), epithet. The accessible name is the English title, as in the masthead.

## not yet designed

- A works shelf and a crew roster. Both will be tables, with tabular lining figures.
- An in-game scheme toggle, if players ask for one.

## Related

- [typography](typography.md): faces, features, hanzi setting, font loading.
- [accessibility](accessibility.md): the rules this design is subordinate to.
- [translation](translation.md): titles and accessible names.
