// The ship's watch bill: the officers aboard, their rank, where they stand,
// and the last thing each did. Read as sentences first; the layout only
// puts them beside a name. See docs/visual-design.md.

///|
/// One officer in the watch bill. Counts are this crossing's unless the ship
/// is in port, when only what the record keeps is left.
struct RosterRow {
  crew : String
  rank : Int64
  you : Bool
  /// The post held, or in port the post named for departure.
  post : @core.Post?
  /// The post the officer spent the most time on this crossing, and its
  /// whole hours. `None` in port or before any time on a post.
  longest : (@core.Post, Int64)?
  /// Ticks left on a watch, if one is running.
  watch : Int64?
  /// The newest action naming the officer, as a sentence for the player and
  /// when it happened.
  last : (String, Int64)?
}

///|
/// The crew member a happening names, if it names one.
fn named_crew(h : @core.Happening) -> String? {
  match h {
    Took(crew~, ..)
    | Signed(crew~)
    | Discharged(crew~)
    | Left(crew~)
    | Stood(crew~)
    | Finished(crew~)
    | Made(crew~, ..)
    | Promoted(crew~, ..) => Some(crew)
    _ => None
  }
}

///|
/// The newest happening naming `crew`, as a sentence, and when it happened.
fn last_action(
  entries : Array[@core.Entry],
  crew : String,
  you~ : String,
  ship~ : String,
) -> (String, Int64)? {
  for i = entries.length() - 1; i >= 0; i = i - 1 {
    let e = entries[i]
    if named_crew(e.happening) == Some(crew) {
      return Some((named(e.happening, you~, ship~), e.at))
    }
  }
  None
}

///|
/// The post `crew` spent the most quarter-hand hours on, if any.
fn longest_post(t : @core.Tally) -> (@core.Post, Int64)? {
  let posts : Array[(@core.Post, Int64)] = [
    (@core.Drive, t.drive),
    (@core.Hull, t.hull),
    (@core.Craft, t.craft),
  ]
  let best = posts.fold(init=(@core.Craft, 0L), (best, p) => {
    if p.1 > best.1 {
      p
    } else {
      best
    }
  })
  if best.1 > 0L {
    Some((best.0, best.1 / (@core.HAND * @core.HOUR)))
  } else {
    None
  }
}

///|
/// The officers aboard, in the order the page shows them: you first, then
/// by rank, then by service number so the list does not move for nothing.
fn roster_rows(
  s : @core.State,
  entries : Array[@core.Entry],
  you~ : String,
  ship~ : String,
) -> Array[RosterRow] {
  let crossing = s.crossing()
  let rows = []
  for crew, officer in s.officers {
    let hand = crossing.bind(c => c.hands.get(crew))
    let tally = crossing.bind(c => c.tallies.get(crew))
    let post = match hand {
      Some(h) => Some(h.post)
      None => officer.post
    }
    let watch = match (crossing, hand) {
      (Some(c), Some(h)) => h.watch.map(w => (w.until - c.t).max(0L))
      _ => None
    }
    rows.push({
      crew,
      rank: s.rank(crew),
      you: crew == you,
      post,
      longest: tally.bind(longest_post),
      watch,
      last: last_action(entries, crew, you~, ship~),
    })
  }
  rows.sort_by((a, b) => {
    if a.you != b.you {
      if a.you {
        -1
      } else {
        1
      }
    } else {
      let by_rank = b.rank.compare(a.rank)
      if by_rank != 0 {
        by_rank
      } else {
        a.crew.compare(b.crew)
      }
    }
  })
  rows
}

///|
/// Whole hours in words: "3 hours", or "Under an hour".
fn post_hours_words(hours : Int64) -> String {
  if hours < 1L {
    "Under an hour"
  } else {
    @words.plural(hours, "hour", "hours")
  }
}

///|
/// Where an officer stands: the post, a watch, or standing down.
fn duty_sentence(row : RosterRow, s : @core.State) -> String {
  let where_ = match s.crossing() {
    Some(_) =>
      match row.post {
        Some(@core.Craft) => "At crafts"
        Some(post) => "On \{@words.post_name(post)}"
        None => "Standing down"
      }
    None =>
      match row.post {
        Some(post) => "In port, to take \{@words.post_name(post)} at departure"
        None => "In port, with no post named"
      }
  }
  let watch = match row.watch {
    Some(ticks) => ", on watch for \{@words.about(ticks)} more"
    None => ""
  }
  let longest = match row.longest {
    Some((post, hours)) => {
      let there = if row.post == Some(post) {
        "there"
      } else {
        match post {
          @core.Craft => "at crafts"
          post => "on \{@words.post_name(post)}"
        }
      }
      " \{post_hours_words(hours)} \{there} this crossing."
    }
    None => ""
  }
  "\{where_}\{watch}.\{longest}"
}

///|
/// The watch bill, as a list: one officer per item, the service number as
/// the name the ship uses. A drawing would add nothing; the prose is the
/// roster.
fn roster_section(model : Model, s : @core.State) -> @rabbita.Html {
  let rows = roster_rows(
    s,
    model.told.entries,
    you=model.officer,
    ship=epithet(model),
  )
  let officers = s.officers.length().to_int64()
  let recruits = s.ship.recruits
  let summary = match officers {
    1L => "You are the only officer aboard."
    n => "\{@words.plural(n, "officer", "officers")} aboard."
  }
  let recruits = if recruits > 0L {
    [
      @html.text(" "),
      @html.text(
        "\{@words.plural(recruits, "recruit", "recruits")} are also aboard.",
      ),
    ]
  } else {
    []
  }
  let items = rows.map(row => {
    let you = if row.you { [@html.span(class="you", "You")] } else { [] }
    let last = match row.last {
      Some((line, at)) =>
        [
          @html.p(class="last", [
            @html.text(line),
            @html.text(" "),
            @html.span(class="when", @words.ago((model.now - at).max(0L))),
          ]),
        ]
      None => []
    }
    @html.li(
      [
        @html.p(
          class="who",
          [
            @html.span(class="service", row.crew),
            ..you,
            @html.text(" "),
            rank_compact(row.rank),
          ],
        ),
        @html.p(class="duty", duty_sentence(row, s)),
        ..last,
      ],
    )
  })
  @html.section([
    @html.h3("Officers"),
    @html.p([@html.text(summary), ..recruits]),
    // Without markers Safari drops list semantics unless asked.
    @html.ul(class="roster", attrs=@html.Attrs::build().role("list"), items),
  ])
}
