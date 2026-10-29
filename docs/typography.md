# typography

Font choices for the game client: EB Garamond for the book voice, Fira Sans for the interface and data, and Noto Serif CJK TC for the hanzi. Everything recommended here is open-licensed, and the OpenType features were checked in the font files.

`public/styles.css` implements these choices; [visual design](visual-design.md) has the palette, type scale and components built on them. `scripts/fonts.mbtx` fetches the faces and subsets them into `public/fonts`.

## Latin

The game has two voices: a book voice for the novel it comes from, and a system voice for a ship that runs on telemetry. Pair them. A single family can do both, but the pairing below gives the anachronism more room and avoids the wide geometric sans that science-fiction interfaces default to. Do not use Eurostile, Microgramma or Bank Gothic; that is the trope.

### EB Garamond + Fira Sans

| role | font | what it gives you |
| --- | --- | --- |
| display and prose | EB Garamond | true small caps in roman and italic; tabular lining by default; oldstyle in tabular and proportional sets |
| UI, labels and data | Fira Sans | true small caps in roman and italic; all four figure sets; slashed zero |

EB Garamond is a Renaissance book face; Fira Sans is a humanist technical sans from the 2010s. They share a humanist skeleton, so the pairing reads as a decision rather than a collision. Use Garamond where the game speaks as a book: titles, ship names in running text, the source codex. Use Fira Sans where the ship speaks as a system: labels, buttons, table text, warnings, and every number that must line up. Tabular lining figures in Fira Sans carry the crossing readouts; a monospace is unnecessary until code or fixed-column editing demands one.

Figure and small-caps behaviour, checked in the Google Fonts builds:

| family | default | tabular lining | tabular oldstyle | proportional oldstyle | small caps |
| --- | --- | --- | --- | --- | --- |
| EB Garamond | tabular lining | default or `tnum` | `onum` | `onum` + `pnum` | `smcp`, `c2sc` in roman and italic |
| Fira Sans | proportional lining | `tnum` | `onum` + `tnum` | `onum` | `smcp`, `c2sc` in roman and italic |

The table is the reason for the pairing. EB Garamond's default figures are already tabular, so data can use it without a switch; Fira Sans gives you the full set for labels and prose in the UI. Fira Sans's tabular oldstyle is rare and useful for a table that should feel typeset rather than computed, but use lining figures for telemetry: oldstyle figures in a column of changing numbers make the digits harder to scan.

### Source Serif 4 + Source Sans 3 + Source Code Pro

| role | font | what it gives you |
| --- | --- | --- |
| display and prose | Source Serif 4 | true small caps in roman only; optical size axis; all four figure sets |
| UI and labels | Source Sans 3 | true small caps in roman only; tabular lining by default; oldstyle in tabular and proportional sets |
| data and telemetry | Source Code Pro | tabular figures by design; oldstyle available; slashed zero |

This is the conservative option: one Adobe superfamily, one set of proportions, one license. Source Serif 4 is a transitional text face rather than a Renaissance one, so the book voice is quieter and the system voice is closer to it. The italic lacks small caps, unlike EB Garamond. Source Sans 3 has no `tnum` feature because its default figures are already tabular. Source Sans 3 and Source Code Pro carry Adobe's Reserved Font Name 'Source', so rename a subset before redistributing it.

### If you want one Latin family

Literata has true small caps in roman and italic, proportional lining, tabular lining and proportional oldstyle, plus an optical size axis. It does not provide tabular oldstyle: `onum` + `tnum` resolves to lining. It is designed for long-form screen reading, so it is a better single-family choice than forcing EB Garamond into UI sizes. Pair it with Fira Sans with tabular lining, or Source Code Pro if you want a mono.

### Recommendation

Use EB Garamond + Fira Sans. It gives the game a book voice and a system voice that are recognizably different, and both faces have the features the interface needs. Use Noto Serif CJK TC for the hanzi. The Source superfamily is the fallback if one family across serif, sans and mono matters more than character; Literata is the fallback if one Latin family is required.

### CSS

The stack below is EB Garamond + Fira Sans. Change the Latin families together if you pick the Source superfamily; the feature settings stay the same.

```css
:root {
  --font-display: "EB Garamond", Georgia, serif;
  --font-ui: "Fira Sans", system-ui, sans-serif;
  --font-han: "Noto Serif CJK TC", "Noto Serif TC", "Songti TC", "PMingLiU", serif;
}

body {
  font-family: var(--font-ui);
  font-synthesis: none;
}

.prose {
  font-family: var(--font-display);
  font-variant-numeric: oldstyle-nums proportional-nums;
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

`font-synthesis: none` is what keeps a missing small-cap or italic from being faked. `font-variant-caps: all-small-caps` uses `smcp` and `c2sc`; with synthesis off, a font that lacks the feature will not get a synthetic one. Check `smcp` and `c2sc` in the build you ship.

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

### What the hanzi is attached to

Every ship has an English epithet and a Chinese conventional name, and its main title is all three identifiers together: `EF-147 顧大嫂 The Tigress` (pennant, conventional name, epithet). The Chinese conventional name is the `conventional_name` column in [`pennants.tsv`](../content/cast/pennants.tsv) (Traditional, from `name_hant` in [`heroes.tsv`](../research/water-margin/heroes.tsv)); the English epithet is the `epithet` column. The conventional name is not a translation of the epithet (母大蟲), and it is the ship's identifier on a ship card, in a register, and anywhere else the ship is named in Chinese. The star (`地陰星`) is metadata, not a name in either language.

### Accessibility

For the full title, the accessible name is the title in the language of the surrounding text: `EF-147 The Tigress` in English, `EF-147 顧大嫂` in Chinese, with the other language's name part marked `aria-hidden="true"` if announcing both would duplicate. For a short reference, match the accessible name to the language of the surrounding text: `The Tigress` in English, `顧大嫂` in Chinese. If the hanzi is the only visible name, add a visually hidden English label. Put `lang="zh-Hant"` on the hanzi span even when it is hidden from assistive technology, so the language of the text is not ambiguous. Do not put hanzi in an `aria-label` without a language tag.

### Loading

Subset the font to the characters you ship. `scripts/fonts.mbtx` does this from the `name_hant` and `star_zh` columns; rerun it if the game shows hanzi from anywhere else. The 108 `name_hant` values and 108 `star_zh` values from [`heroes.tsv`](../research/water-margin/heroes.tsv) use 251 unique characters. A subset of Noto Serif CJK TC Regular to those characters is about 85 KB as WOFF2, and the two weights the game uses about 170 KB. That is small enough to self-host and preload the weight used above the fold. Do not hotlink Google Fonts: the game should work offline, and the CSS request is a privacy leak.

Noto Serif CJK TC has no Reserved Font Name, so a subset can keep the name. Source Han Serif TW and Source Han Sans TC carry the Reserved Font Name 'Source'; rename a subset before redistributing it. Subsetting counts as a modification under the OFL.

Fallback stack: `"Noto Serif CJK TC", "Songti TC", "PMingLiU", serif`. Test with the webfont disabled; a Japanese fallback will show Japanese glyph forms.

## Sources

- [EB Garamond](https://github.com/octaviopardo/EBGaramond12)
- [Fira Sans](https://github.com/mozilla/Fira)
- [Atkinson Hyperlegible Next](https://github.com/googlefonts/atkinson-hyperlegible-next)
- [Source Serif](https://github.com/adobe-fonts/source-serif)
- [Source Han Serif](https://github.com/adobe-fonts/source-han-serif)
- [Noto CJK](https://github.com/notofonts/noto-cjk)
- [Chiron Sung HK](https://github.com/chiron-fonts/chiron-sung-hk)
- [Requirements for Chinese Text Layout](https://www.w3.org/TR/clreq/)
- [SIL Open Font License FAQ](https://openfontlicense.org/ofl-faq/)

## Related

- [translation](translation.md): ship titles and accessible names.
- [accessibility](accessibility.md): announcements and screen-reader rules.
- [cast](cast.md): the pipeline that produces ship text.
