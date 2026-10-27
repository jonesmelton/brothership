# water margin: the 108 stars

`heroes.tsv` has one row per hero (rank 1–108) and merges three sources. Each
column's prefix or name tells you which source it came from. To rebuild it,
from `research/water-margin`:

```
moon run merge.mbtx sources/en-wikipedia-108-heroes.wikitext \
  sources/zh-wikipedia-yibaidanbajiang.wikitext \
  sources/shapiro-via-artofmemory.txt heroes.tsv
```

`heroes.tsv` is the reference output; diff it after a rebuild to see how a
parser change affects the merged data.

## sources

| key        | source                                                                                                  | retrieved  | revision                    | license      |
| ---------- | ------------------------------------------------------------------------------------------------------- | ---------- | --------------------------- | ------------ |
| `wp`       | en.wikipedia, [108 Heroes](https://en.wikipedia.org/wiki/108_Heroes)                                     | 2026-10-26 | 1375402679 (2026-09-17)     | CC BY-SA 4.0 |
| `zh`       | zh.wikipedia, [一百单八将](https://zh.wikipedia.org/wiki/一百单八将)                                      | 2026-10-26 | 93619684 (2026-07-23)       | CC BY-SA 4.0 |
| `shapiro`  | Sidney Shapiro, *Outlaws of the Marsh* (1980), transcribed by user Zadignose on the [Art of Memory forum](https://forum.artofmemory.com/t/108-heroes-from-outlaws-of-the-marsh-how-would-you-accomplish-this/28867) | 2026-10-26 | posts 2–3, 2013-11-06/07    | copyrighted translation; nicknames only |

`sources/` holds the raw wikitext and the forum list as fetched.

## columns

Unprefixed columns come from `wp`, except for these:

- `rank`, `tier`: the ranking. 天罡 is 1–36 and 地煞 is 37–108. All three sources agree on it.
- `name_zh`, `nick_zh`: from `zh`, written as that page writes them. The page
  mixes scripts (盧俊義 but 白胜, 时迁).
- `name_hans`, `name_hant`: from `wp`'s name cell, which gives the simplified
  form first and the traditional form last.
- `nick_en_shapiro`, `name_shapiro`: from `shapiro`.
- `zh:*`: every column of the `zh` table, verbatim: occupation, chapter of
  first appearance (初登場回數), chapter of joining (入山時回數), Liangshan
  post, post after amnesty, fate, and notes.
- `conflicts`: where `wp` and `zh` disagree on the star, name or nickname
  characters.

The tsv is plain: no quoting and no tabs or newlines inside fields. `nick_en_wp`
joins multiple nicknames with ` | `. `nick_wp_raw` keeps the original cell.
Where a source cell had a line break (`<br>`):

- In `wp` columns, a break before a parenthetical becomes a space, and a break
  after `,` or `;` is dropped. Any other break becomes `; `.
- In `zh:*` columns, every break becomes a single space. Some of them wrap one
  phrase (前任梁山泊 第四位頭領) and others separate two items (與瓊英結婚
  其子張節…), and the markup doesn't say which. `fate_wp` and `other_names_wp` exist only for the 36 天罡,
because the `wp` 地煞 table has no such columns. For those 72, `zh:後續發展`
has the fate.

## caveats

- **Variant characters.** `zh` uses a few Japanese shinjitai forms (赤髪鬼,
  挿翅虎, 地満星). `wp` uses the standard traditional forms (赤髮鬼, 插翅虎,
  地滿星). For traditional characters, prefer `wp`'s `nick_zh_wp`/`star_zh`
  over `zh`.
- **Real textual variants**, which differ between editions of the novel:
  - 地羈星 vs 地稽星 (#81)
  - 聖水將 vs 聖水將軍 (#44)
  - 神火將 vs 神火將軍 (#45)
  - 浪裏白條 vs 浪裡白跳 (#30)
  - 美髯公 vs 美鬚公 (#12)
- **Shi En's rank.** `zh` notes that some editions put 施恩 at #93 rather than
  #85, which moves #86–93 up by one. All three sources here use #85.
- **`shapiro` is secondhand.** It is a forum post typed from the book, and it
  has typos. "Zhang Qin" for #16 should be Zhang Qing. The others are "LiLi"
  (Li Li), "Wang Dinliu" (Wang Dingliu), "The Tigres" (Tigress) and "Si Qian"
  (Shi Qian). I kept them as written in `sources/` and in the tsv. The forum
  numbered the 地煞 1–72; I renumbered them 37–108. Check against a copy of the
  book before quoting it.
- **Mixed name forms in `shapiro`.** Shapiro sometimes translates the name
  instead of romanizing it: "Sagacious Lu" (魯智深), "Ruan the Second/Fifth/Seventh"
  (阮小二/五/七) and "Mistress Gu" (顧大嫂).
- **Licensing.** Both Wikipedia tables are CC BY-SA, so anything that ships
  derived text needs attribution, and share-alike applies to that text. The
  names and nicknames themselves come from a 14th-century public-domain novel.
  The *English renderings* of nicknames are the translators' work. Pick `wp`
  or `shapiro` deliberately, or write our own translations from `nick_zh`.
