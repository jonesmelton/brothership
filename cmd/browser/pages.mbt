// The check-in's three pages: which one is shown, what is new on each, and
// the bar of links between them. See docs/visual-design.md.

///|
/// The pages in the order the bar lists them.
let all_pages : Array[@words.Page] = [You, Voyage, Ship]

///|
/// The page's name in a link's `href` and in the address.
fn page_slug(page : @words.Page) -> String {
  match page {
    You => "you"
    Voyage => "voyage"
    Ship => "ship"
  }
}

///|
/// The page an address names: `#you`, `#voyage` or `#ship`, with or without
/// the `#`. An empty or unknown one is You.
fn page_from_hash(hash : String) -> @words.Page {
  let slug = hash.to_lower().trim(chars="#").to_owned()
  all_pages.iter().find_first(p => page_slug(p) == slug).unwrap_or(You)
}

///|
/// The newest story `seq` the player has viewed on each page, for the
/// counts in the bar. Negative until known.
struct Viewed {
  you : Int64
  voyage : Int64
  ship : Int64
} derive(Eq, Debug)

///|
fn Viewed::get(self : Viewed, page : @words.Page) -> Int64 {
  match page {
    You => self.you
    Voyage => self.voyage
    Ship => self.ship
  }
}

///|
/// `page` viewed up to `seq`; never moves back.
fn Viewed::mark(self : Viewed, page : @words.Page, seq : Int64) -> Viewed {
  match page {
    You => { ..self, you: self.you.max(seq), }
    Voyage => { ..self, voyage: self.voyage.max(seq), }
    Ship => { ..self, ship: self.ship.max(seq), }
  }
}

///|
/// Every page not yet known set to `seq`: a first visit has nothing unread.
fn Viewed::settle(self : Viewed, seq : Int64) -> Viewed {
  let known = (n : Int64) => if n < 0L { seq } else { n }
  { you: known(self.you), voyage: known(self.voyage), ship: known(self.ship), }
}

///|
/// As kept in `localStorage`: the three seqs in page order.
fn Viewed::name(self : Viewed) -> String {
  "\{self.you},\{self.voyage},\{self.ship}"
}

///|
fn Viewed::parse(s : String) -> Viewed? {
  let parts = s.split(",").collect()
  guard parts.length() == 3 else { None }
  Some({
    you: @string.parse_int64(parts[0].to_owned()),
    voyage: @string.parse_int64(parts[1].to_owned()),
    ship: @string.parse_int64(parts[2].to_owned()),
  }) catch {
    _ => None
  }
}

///|
/// How many of `entries` are on a page, per `on`, and newer than `viewed`.
fn unread(
  entries : Array[@core.Entry],
  viewed : Int64,
  on : (@core.Entry) -> Bool,
) -> Int32 {
  entries.iter().filter(e => e.seq > viewed && on(e)).count()
}

///|
/// How many entries are new on `page`.
fn Model::unread_on(self : Model, page : @words.Page) -> Int32 {
  let entries = self.told.entries
  unread(entries, self.viewed.get(page), e => {
    @words.page_of(e, you=self.officer, story=entries) == page
  })
}

///|
/// The bar of links between the pages, outside `main`. Each link's name
/// carries the count; the figure beside the name is for the eye only.
fn pages_nav(model : Model) -> @rabbita.Html {
  @html.nav(
    class="pages",
    attrs=@html.Attrs::build().aria_label("Pages"),
    all_pages.map(p => {
      let news = model.unread_on(p)
      let attrs = if p == model.page {
        @html.Attrs::build().aria_current("page")
      } else {
        @html.Attrs::build()
      }
      let count = if news == 0 {
        []
      } else {
        [
          @html.span(
            class="count",
            attrs=@html.Attrs::build().aria_hidden("true"),
            news.to_string(),
          ),
          @html.span(class="visually-hidden", ", \{news} new"),
        ]
      }
      @html.a(
        href="#\{page_slug(p)}",
        class=if p == model.page { "current" } else { "" },
        attrs~,
        [@html.span(p.name()), ..count],
      )
    }),
  )
}

///|
/// `page` shown. Going to the page already shown changes nothing; going
/// elsewhere reads that page's entries and drops the last choice's effect.
fn Model::goto(self : Model, page : @words.Page) -> Model {
  guard page != self.page else { self }
  {
    ..self,
    page,
    effect: [],
    viewed: self.viewed.mark(page, self.told.last()),
  }
}

///|
/// What the last choice changed, kept for the You page and spoken politely
/// unless the player wants nothing read aloud. The next choice replaces it.
fn Model::with_effect(self : Model, lines : Array[String]) -> Model {
  let said = if self.hear == Nothing || lines.is_empty() {
    self.said
  } else {
    { polite: lines.join(" "), assertive: "", count: self.said.count + 1, }
  }
  { ..self, effect: lines, said, }
}

///|
/// The watch to offer again, in hours: the last length chosen, capped at
/// the rank's longest, when `you`'s latest change this crossing was a watch
/// stood to its end. Nothing once a post was taken or left since.
fn reup(
  entries : Array[@core.Entry],
  you : String,
  last : Int64,
  longest : Int64,
) -> Int64? {
  guard last > 0L else { None }
  let n = last.min(longest)
  for i = entries.length() - 1; i >= 0; i = i - 1 {
    match entries[i].happening {
      Stood(crew~) if crew == you => return if n > 0L { Some(n) } else { None }
      Took(crew~, ..) | Left(crew~) if crew == you => return None
      Departed => return None
      _ => ()
    }
  }
  None
}

///|
fn reup_label(hours : Int64) -> String {
  "Stand " + @words.plural(hours, "more hour", "more hours")
}

///|
/// The ledger as `localStorage` kept it, or `None` for nothing or damage.
fn parse_ledger(s : String) -> @words.Ledger? {
  guard s != "" else { None }
  try @json.from_json(@json.parse(s)) catch {
    _ => None
  } noraise {
    ledger => Some(ledger)
  }
}
