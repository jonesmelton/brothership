# plan: check-in accessibility fixes

Fix the failures found in a browser run-through of the check-in on
2026-10-28. Three break commitments in `docs/accessibility.md`: focus is
lost when a control removes itself, pressed buttons are unreadable in forced
colors, and the page scrolls sideways at large text sizes. The rest are
smaller: a static page title, labels that repeat headings, inconsistent
capitalization of button labels, iOS text size, and a type-scale entry that
drifted from the stylesheet.

Read these first: `AGENTS.md`, `docs/accessibility.md`,
`docs/visual-design.md` and `public/styles.css`. Every change is in
`cmd/browser` and `public/styles.css`; nothing touches `core`, the sync
protocol or the store.

## facts established before writing this

Checked on 2026-10-28 against the repo at `a110c1b`.

- `make dev` serves the game at `http://127.0.0.1:4300`. warren writes its
  scratch directory under `/tmp` regardless of `TMPDIR`, so a sandboxed
  agent has to run `make dev` outside the sandbox.
- axe-core 4.3.5 (`wcag2a`, `wcag2aa`, `wcag21aa`, `wcag22aa`,
  `best-practice`) reports no violations on the ship chooser or the
  check-in, in light or dark. None of the failures below are caught by axe.
  A copy is at `~/.config/yarn/global/node_modules/axe-core/axe.min.js`.
- Every button is at least 44 by 44 CSS px. The stylesheet has no animation
  or transition. Focus stays put through the 5 s `Tock` and 15 s `Poll`
  re-renders.
- Focus drops to `<body>` after: choosing a ship from "Choose a ship";
  choosing a watch length (the `Watch` buttons are replaced by "On watch.
  Changing post breaks it."); pressing "Cancel the order" (the button
  removes itself). "Leave the crew" also removes itself and every group but
  `Post`, by reading `choices` in `cmd/browser/main.mbt`; it was not run.
- Toggles whose buttons persist (post, craft, refit, standing order) keep
  focus.
- With `forced-colors: active` emulated through CDP
  (`Emulation.setEmulatedMedia`), every `aria-pressed="true"` button shows a
  solid box with no visible label. Chrome draws a `Canvas`-colored backplate
  behind text in forced colors; the label is `HighlightText` on that
  backplate. The voyage track's groove (`--rule` background) also
  disappears, which leaves only the burn fill visible.
- Horizontal overflow:
  - 320 px wide, root `font-size: 100%`: none.
  - 320 px wide, root `200%`: `scrollWidth` 334. Source: `.track .stretch`,
    whose `.label` is `white-space: nowrap` in a flex item with the default
    `min-width: auto`.
  - 390 px wide, root `310%` (about iOS's largest accessibility size):
    `scrollWidth` 518. Sources: the track, and the "Engineering" button,
    whose single word is wider than the column.
- `index.html` sets `<title>brothership</title>` and nothing changes it.
- The legend "Ship" sits directly under the `h1` "Choose a ship" and under
  the `h2` "Other ships". `docs/accessibility.md` says "No label that
  repeats a heading".
- Post and craft buttons are capitalized ("Drive", "Art"). Standing-order
  and refit buttons are not ("the hull at the coast", "baffles"), because
  they reuse `post_name`, `phase_name` and `refit_name` from `words.mbt`,
  which are written for use inside sentences.
- `.track .label` is `0.875rem`. `docs/visual-design.md` says labels stay at
  1rem and does not list the track label in its type scale.
- Rabbita runs a command after the DOM patch when it is built with
  `@cmd.custom_cmd(f, kind=AfterRender)` from
  `moonbit-community/rabbita/cmd`. `@rabbita` re-exports `effect`, `none`,
  `batch` and `delay` but not `custom_cmd`, so `cmd/browser/moon.pkg` must
  import `moonbit-community/rabbita/cmd`. A plain `@rabbita.effect` may run
  before the patch, when the element to focus does not exist yet.
- `@html.Attrs::tabindex(Int32)` and `@html.Attrs::id` exist.

## decisions this plan makes

State them in the commit messages. Neither needs a `docs/decisions.md`
entry unless the reviewer disagrees.

- Focus moves only in response to the player's own input, never on a poll,
  a resync or a settled receipt. `docs/accessibility.md` says things don't
  move without the player asking; a focus move the player didn't cause is
  that kind of move.
- When the control the player pressed disappears, focus goes to the
  nearest thing that still exists and names what happened: the masthead
  `h1` after boarding a ship, otherwise the fieldset of the group the
  control was in.

## steps

Write each test before its change and watch it fail. The pure functions in
steps 1, 3 and 5 get `_wbtest.mbt` tests in the style of
`cmd/browser/words_wbtest.mbt`. The CSS steps have no test harness; verify
them in a browser as described under "verifying in a browser", and record
the numbers in the commit message. Ask the user before adding a browser
test harness: that is a larger change than this plan.

Commit after each step. Run `make check` before handing off.

### 1. focus after a control disappears

1. Give each choice group a stable id and make it a programmatic focus
   target. `group` in `cmd/browser/main.mbt` takes an id (`"post"`,
   `"watch"`, `"order"`, `"craft"`, `"refit"`) and renders the fieldset with
   `id` and `tabindex="-1"`.
2. Give the masthead `h1` `id="title"` and `tabindex="-1"`.
3. Add a pure function from the proposed intent to the id that should take
   focus, `None` when the pressed button survives:

   | intent | focus |
   | --- | --- |
   | `Watched(..)` | `"watch"` |
   | `Ordered(order=None)` | `"order"` |
   | `Left` | `"post"` |
   | anything else | `None` |

   Test it first.
4. In `update`, on `Propose(intent)` that the local prediction accepts,
   batch an after-render command that focuses that id. On `Choose(ship)`,
   focus `"title"`. Add the focus call as an `extern "js"` in
   `cmd/browser/js.mbt`, next to the existing `localStorage` externs, that
   does nothing if the id is missing. Import `moonbit-community/rabbita/cmd`
   for `custom_cmd`.
5. Do not move focus on `Loaded`, `Settled`, `Poll` or `Tock`, or when the
   prediction refuses the intent.
6. Style the new focus targets like the buttons: in `public/styles.css`,
   `[tabindex="-1"]:focus-visible` gets the 3px `--accent` outline with a
   2px offset. Leave `:focus` without `:focus-visible` unstyled, so a mouse
   click doesn't draw a ring around a fieldset.

Expected result: after each of the five actions in the facts above,
`document.activeElement` is the `h1` or the named fieldset, never `body`.

### 2. forced colors

1. In the `@media (forced-colors: active)` block of `public/styles.css`, add
   `forced-color-adjust: none` to `.checkin button[aria-pressed="true"]`.
   Every color that rule sets is already a system color, so opting out of
   the adjustment is safe.
2. In the same block, give `.track .bar` a `GrayText` background so the
   groove stays visible next to the `CanvasText` fill.

Expected result: with forced colors emulated, pressed labels read as
`HighlightText` on `Highlight`, and all three track stretches are visible.

### 3. no horizontal scrolling at large text

1. The "Engineering" button: add `overflow-wrap: break-word` and
   `hyphens: auto` to `.checkin button`, so a word wider than the column
   breaks inside the button. `lang="en"` on `<html>` already lets `hyphens`
   work.
2. The voyage track: give `.track .stretch` `min-width: 0` so a stretch can
   be narrower than its label, then stop the labels colliding. Make
   `.track` a size container (`container-type: inline-size`) and, below a
   width in `em` at which the three labels no longer fit (find it by
   measurement; it is near `20em`), hide the labels of stretches other than
   `.now` with `visibility: hidden`. Measuring in `em` means the query
   responds to text size as well as to viewport width. The current phase is
   still named in the sentence above the track, so nothing is lost.
3. The current stretch can itself be narrower than its label, the burn in
   particular. Let `.now .label` overflow its stretch to the right, but not
   the track: test the case where the burn is the current phase at the
   largest size.
4. Update "the voyage track" in `docs/visual-design.md` to describe the
   narrow behavior.

If the container query turns out not to work in warren's build or in iOS
Safari 16 or later, stop and ask rather than replacing it with JavaScript.

Expected result: `document.documentElement.scrollWidth` equals
`clientWidth` at 320 px with root `200%` and at 390 px with root `310%`,
in every phase.

### 4. the page title

1. Add a pure function from the model to the document title: the ship's
   English title (`EF-147 The Tigress`) when aboard, `brothership` on the
   ship chooser. The Chinese conventional name stays out, as it does in the
   accessible name of the `h1` (`docs/translation.md`). Test it first.
2. Set `document.title` in an effect when the ship changes and when the
   ship list arrives.

### 5. labels that repeat headings

`ship_choices` renders the ships inside `group("Ship", ...)`. Render them
without a fieldset or legend: a `div` with the fieldset's flex layout.
`.checkin fieldset` in `public/styles.css` carries that layout today; give
the new container a class with the same rules. The heading above already
names the list. Keep the buttons and their `aria-pressed`.

### 6. capitalization

Choice buttons use sentence case: "The drive at the coast", "Crafts at the
approach", "Baffles". Add label functions for buttons rather than changing
`post_name`, `phase_name` and `refit_name`, which are used mid-sentence.
Extend the existing tests in `words_wbtest.mbt` to cover the new labels.

### 7. iOS text size

Safari on iOS does not apply the system text size (Dynamic Type) to a page
whose root font size is the default 16px. It does apply it to
`font: -apple-system-body`, which on macOS Safari is 13px, so scope it to
iOS:

```css
@supports (font: -apple-system-body) and (-webkit-touch-callout: default) {
  html {
    font: -apple-system-body;
  }
}
```

`body` already sets `font-family`, so the faces are unaffected. This step
cannot be verified in Chrome. Mark it unverified in the commit and ask the
user to check it on an iPhone at the largest accessibility text size. It
interacts with step 3: that size is where the overflow matters most.

### 8. the track label's size

Add the track label to the type scale in `docs/visual-design.md` at
`0.875rem`, with a note that it is `aria-hidden` and repeats a sentence.
Do not change the stylesheet.

## out of scope

- Announcements. Taking a post changes the "You" section silently; only the
  button's pressed state tells a screen reader anything. `docs/visual-design.md`
  lists the event log and its announcements as not yet designed, and
  `docs/accessibility.md` asks for live regions to be tested on an iOS
  device before the game is built around them. That is its own plan.
- A confirmation for "Leave the crew".
- A browser test harness, unless the user agrees to one.

## verifying in a browser

Use `bb browser-automation` with a headless local session (see
`bb guide`). In a script, `const p = await browser.getPage("main")`, then:

- Phone size: `await p.setViewport({width: 390, height: 844})`.
- 400% zoom on a 1280 px window: `{width: 320, height: 640}`.
- Text size: `await p.evaluate(() => document.documentElement.style.fontSize = "310%")`.
- Overflow: compare `document.documentElement.scrollWidth` with
  `clientWidth`, and list elements whose `getBoundingClientRect().right`
  exceeds `clientWidth`.
- Dark scheme: `await p.emulateMediaFeatures([{name: "prefers-color-scheme", value: "dark"}])`.
- Forced colors: `emulateMediaFeatures` rejects `forced-colors`; use CDP:
  `const c = await p.createCDPSession(); await c.send("Emulation.setEmulatedMedia", {features: [{name: "forced-colors", value: "active"}]})`.
- Focus: drive by keyboard (`p.keyboard.press("Tab")`, `"Enter"`,
  `"Space"`), then read `document.activeElement`.
- axe: `await p.addScriptTag({path: "<copy of axe.min.js>"})`, then
  `await p.evaluate(async () => (await axe.run()).violations)`. Copy the
  file somewhere the browser host can read first; the sandbox may block the
  original path.

Re-run axe after every step; it must still report nothing.
