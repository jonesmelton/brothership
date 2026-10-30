///|
test "arrival words coarsen with distance" {
  let h = 3600L
  let at : Array[Int64] = [
    0,
    59 * 60,
    h,
    89 * 60,
    90 * 60,
    5 * h,
    6 * h,
    13 * h,
    35 * h,
    36 * h,
    80 * h,
  ]
  debug_inspect(
    at.map(in_words),
    content=(
      #|[
      #|  "within the hour",
      #|  "within the hour",
      #|  "in about an hour",
      #|  "in about an hour",
      #|  "in about 2 hours",
      #|  "in about 5 hours",
      #|  "in about 6 hours",
      #|  "in about 12 hours",
      #|  "in about 36 hours",
      #|  "in about 2 days",
      #|  "in about 3 days",
      #|]
    ),
  )
}

///|
test "an empty ship says so instead of counting zeroes" {
  let p = @ships.fleet()[0].profile
  let (_, s) = p.due(
    @core.State::initial(p.ship(seed=1), profile=p.name),
    1_800_000_000,
    officer=_ => true,
  )
  let (_, sea) = p.due(s, 1_800_000_600, officer=_ => true)
  debug_inspect(
    where_sentences(sea),
    content=(
      #|[
      #|  "Burning toward Occitan.",
      #|  "15.7 of the 15.7 light-years from Kerala still to go.",
      #|  "Under a day has passed at Kerala and Occitan since departure.",
      #|  "Arriving in about 18 hours, if the drive stays as set.",
      #|  "The coast begins in about 6 hours.",
      #|  "Hull at 100%.",
      #|  "Drive at 35% of full burn, with none of the 5 hands it needs.",
      #|  "Nobody is on a post yet.",
      #|  "The ship asks for hands on the drive.",
      #|]
    ),
  )
}

///|
test "a voyage from port to its first moments, in sentences" {
  let p = @ships.fleet()[0].profile
  let (_, s) = p.due(
    @core.State::initial(p.ship(seed=1), profile=p.name),
    1_800_000_000,
    officer=_ => true,
  )
  debug_inspect(
    where_sentences(s),
    content=(
      #|[
      #|  "In port at Kerala, bound for Occitan, 15.7 light-years away.",
      #|  "Stores load in about 10 minutes, and the ship departs then.",
      #|  "Hull at 100%.",
      #|]
    ),
  )
  debug_inspect(
    you_sentences(s, "ann"),
    content=(
      #|["You are not aboard."]
    ),
  )
  let s = s.apply(Crew(crew="ann", intent=Signed)) catch { _ => panic() }
  debug_inspect(
    you_sentences(s, "ann"),
    content=(
      #|["You have no post. Choose one to work in port and take when the ship departs."]
    ),
  )
  debug_inspect(
    leaving_sentences(s, "ann"),
    content=(
      #|["You may leave the ship before it departs, and choose another."]
    ),
  )
  let s = s.apply(Crew(crew="ann", intent=Posted(post=Craft))) catch {
    _ => panic()
  }
  debug_inspect(
    you_sentences(s, "ann"),
    content=(
      #|["Crafts do nothing in port. You go to your craft when the ship departs."]
    ),
  )
  let (_, sea) = p.due(s, 1_800_000_600, officer=_ => true)
  let sea = sea.apply(Crew(crew="ann", intent=Posted(post=Drive))) catch {
    _ => panic()
  }
  debug_inspect(
    where_sentences(sea),
    content=(
      #|[
      #|  "Burning toward Occitan.",
      #|  "15.7 of the 15.7 light-years from Kerala still to go.",
      #|  "Under a day has passed at Kerala and Occitan since departure.",
      #|  "Arriving in about 15 hours, if the drive stays as set.",
      #|  "The coast begins in about 4 hours.",
      #|  "Hull at 100%.",
      #|  "Drive at 58% of full burn, with 1 of the 5 hands it needs.",
      #|  "1 hand on the drive, 0 on the hull, 0 at crafts.",
      #|  "The ship asks for hands on the drive.",
      #|]
    ),
  )
  debug_inspect(
    you_sentences(sea, "ann"),
    content=(
      #|["You are on the drive.", "Your craft is art."]
    ),
  )
}

///|
test "happenings in sentences, from where the player stands" {
  let hs : Array[@core.Happening] = [
    Departed,
    Began(phase=Coast),
    Began(phase=Arrived),
    Docked(recruits=2, landing=no_landing()),
    Opened(hazard=Breach),
    Missed(hazard=Flare),
    Landed(refit=Baffles, level=2),
    Asked(post=None),
    Took(crew="ann", post=Hull),
    Took(crew="bo", post=Craft),
    Stood(crew="bo"),
    Finished(crew="ann"),
    Made(crew="ann", craft=Engineer, units=3 * 57600 + 100, percent=140),
    Made(crew="bo", craft=Artist, units=100, percent=100),
    Spoke(line="Who will sit with me?", about=4),
  ]
  debug_inspect(
    hs.map(h => told(h, you="ann", ship="The Tigress")),
    content=(
      #|[
      #|  "The ship left port.",
      #|  "The coast began.",
      #|  "The ship arrived.",
      #|  "The ship docked, and 2 recruits joined.",
      #|  "A breach opened on the hull.",
      #|  "A flare was missed.",
      #|  "A refit landed: baffles to level 2, hull wears 44% less.",
      #|  "The ship stopped asking for hands.",
      #|  "You took the hull.",
      #|  "A hand went to crafts.",
      #|  "A hand stood a watch to its end.",
      #|  "You finished a work.",
      #|  "You made 3 crew-hours of engineering at 140%.",
      #|  "A hand made under a crew-hour of art at 100%.",
      #|  "The Tigress: Who will sit with me?",
      #|]
    ),
  )
}

///|
test "a demand interrupts, crew moves are quiet, and a line takes its cause's priority" {
  let story : Array[@core.Entry] = [
    { seq: 4, at: 0, happening: Opened(hazard=Breach), },
    { seq: 5, at: 0, happening: Took(crew="bo", post=Hull), },
    { seq: 6, at: 0, happening: Finished(crew="ann"), },
    {
      seq: 9,
      at: 0,
      happening: Made(crew="ann", craft=Engineer, units=1, percent=100),
    },
    {
      seq: 10,
      at: 0,
      happening: Made(crew="bo", craft=Artist, units=1, percent=100),
    },
    { seq: 7, at: 0, happening: Spoke(line="Hands to the hull!", about=4), },
    { seq: 8, at: 0, happening: Spoke(line="Welcome.", about=5), },
  ]
  debug_inspect(
    story.map(e => priority(e, you="ann", story~)),
    content=(
      #|[Interrupt, Quiet, Announce, Quiet, Quiet, Interrupt, Announce]
    ),
  )
}

///|
test "how long ago, coarsely" {
  let at : Array[Int64] = [0, 59, 60, 7 * 60, 50 * 60, 3 * 3600, 3 * 86400]
  debug_inspect(
    at.map(ago),
    content=(
      #|[
      #|  "just now",
      #|  "just now",
      #|  "1 minute ago",
      #|  "5 minutes ago",
      #|  "50 minutes ago",
      #|  "about 3 hours ago",
      #|  "about 3 days ago",
      #|]
    ),
  )
}

///|
test "button labels are sentence case and need no article" {
  debug_inspect(
    [@core.Drive, @core.Hull, @core.Craft].map(post_label),
    content=(
      #|["Drive", "Hull", "Craft"]
    ),
  )
  debug_inspect(
    [@core.Artist, @core.Engineer].map(craft_label),
    content=(
      #|["Art", "Engineering"]
    ),
  )
  debug_inspect(
    @core.refits.map(refit_label),
    content=(
      #|["Baffles", "Plating", "Injectors", "Coils"]
    ),
  )
}

///|
test "ranks have a title, a name, an abbreviation and an insignia" {
  let ranks : Array[Int64] = [-1, 0, 1, 2, 3, 4, 9]
  debug_inspect(
    ranks.map(rank_title),
    content=(
      #|[
      #|  "Ensign",
      #|  "Ensign",
      #|  "Lieutenant junior grade",
      #|  "Lieutenant",
      #|  "Lieutenant commander",
      #|  "Commander",
      #|  "Commander",
      #|]
    ),
  )
  debug_inspect(
    ranks.map(rank_name),
    content=(
      #|[
      #|  "ensign",
      #|  "ensign",
      #|  "lieutenant junior grade",
      #|  "lieutenant",
      #|  "lieutenant commander",
      #|  "commander",
      #|  "commander",
      #|]
    ),
  )
  debug_inspect(
    ranks.map(rank_abbreviation),
    content=(
      #|["ENS", "ENS", "LTJG", "LT", "LCDR", "CDR", "CDR"]
    ),
  )
  debug_inspect(
    ranks.map(rank_insignia),
    content=(
      #|["○", "○", "●", "●●", "●●●", "★", "★"]
    ),
  )
}

///|
test "a promotion is told in full and announced" {
  let tally : @core.Tally = {
    drive: 0,
    hull: 0,
    craft: 0,
    regard: 0,
    work: 0,
    watches_stood: 0,
    watches_broken: 0,
    served: 0,
  }
  let h : @core.Happening = Promoted(crew="0", rank=3L, tally~)
  debug_inspect(
    [told(h, you="0", ship="The Tigress"), told(h, you="1", ship="The Tigress")],
    content=(
      #|[
      #|  "You were promoted to lieutenant commander.",
      #|  "A hand was promoted to lieutenant commander.",
      #|]
    ),
  )
  let e : @core.Entry = { seq: 1, at: 0, happening: h, }
  debug_inspect(
    [priority(e, you="0", story=[e]), priority(e, you="1", story=[e])],
    content=(
      #|[Announce, Quiet]
    ),
  )
  debug_inspect(
    [page_of(e, you="0", story=[e]), page_of(e, you="1", story=[e])],
    content=(
      #|[You, Ship]
    ),
  )
}

///|
test "the readout is the shipping forecast, front-loaded" {
  debug_inspect(
    readout(sea()),
    content=(
      #|"Burn. Occitan in about 18 hours. Hull 100%. Drive 35%, 0 of 5 hands."
    ),
  )
  debug_inspect(
    readout(sea(posts=[Drive, Hull])),
    content=(
      #|"Burn. Occitan in about 15 hours. Hull 100%. Drive 58%, 1 of 5 hands."
    ),
  )
  debug_inspect(
    readout(sea(posts=[Drive], ticks=7 * 3600L)),
    content=(
      #|"Coast. Occitan in about 6 hours. Hull 28%."
    ),
  )
}

///|
test "what the page adds to the readout leaves out what it says" {
  for line in where_rest(sea(posts=[Drive, Hull])) {
    assert_false(line.contains("Hull at"))
    assert_false(line.contains("Arriving"))
  }
}

///|
test "a post says what it would change, and nothing for the one held" {
  guard sea(posts=[Drive, Hull]).crossing() is Some(c) else { panic() }
  let effects = (crew : String) => {
    let posts : Array[@core.Post] = [Drive, Hull, Craft]
    posts.map(p => post_effect(c, crew, p))
  }
  debug_inspect(
    effects("0"),
    content=(
      #|["", "hull unchanged", "banks work for your craft"]
    ),
  )
  debug_inspect(
    effects("1"),
    content=(
      #|["arrival about the same", "", "banks work for your craft"]
    ),
  )
  debug_inspect(
    effects("nobody"),
    content=(
      #|[
      #|  "arrive about 2 hours sooner",
      #|  "hull unchanged",
      #|  "banks work for your craft",
      #|]
    ),
  )
}

///|
test "a post's effect on a worn hull" {
  guard sea(posts=[Drive, Hull, Craft]).crossing() is Some(c) else { panic() }
  let worn = { ..c, hull: 500_000_000L, band: 1L, }
  let posts : Array[@core.Post] = [Drive, Hull, Craft]
  debug_inspect(
    ["0", "1", "2"].map(crew => posts.map(p => post_effect(worn, crew, p))),
    content=(
      #|[
      #|  ["", "hull mends faster", "banks work for your craft"],
      #|  ["arrival about the same", "", "banks work for your craft"],
      #|  ["arrive about 2 hours sooner", "hull mends faster", ""],
      #|]
    ),
  )
}

///|
test "a post's effect on a hull that wears" {
  guard sea(posts=[Drive, Drive, Drive, Drive, Drive]).crossing() is Some(c) else {
    panic()
  }
  let worn = { ..c, hull: 500_000_000L, band: 1L, }
  let posts : Array[@core.Post] = [Drive, Hull]
  debug_inspect(
    posts.map(p => post_effect(worn, "0", p)) +
    posts.map(p => post_effect(worn, "9", p)),
    content=(
      #|[
      #|  "",
      #|  "hull stops wearing",
      #|  "arrival about the same",
      #|  "hull stops wearing",
      #|]
    ),
  )
}

///|
test "a listing in one sentence" {
  let at = (whereabouts : @core.Whereabouts, crossings : Int64) => {
    listing_sentence(
      { id: "x", name: "x", crossings, whereabouts, run: 0, officers: 2, },
      now=1000,
    )
  }
  inspect(
    at(InPort(departs=1300), 0),
    content="In port at Kerala, leaving for Occitan in about 5 minutes. 2 officers aboard.",
  )
  inspect(
    at(Underway(arrives=Some(1000 + 7 * 3600)), 1),
    content="Between Occitan and Tigray, arriving in about 6 hours. 2 officers aboard.",
  )
  inspect(
    at(Underway(arrives=Some(900)), 1),
    content="Arrived at Tigray, docking. 2 officers aboard.",
  )
  inspect(
    at(Underway(arrives=None), 1),
    content="Between Occitan and Tigray. 2 officers aboard.",
  )
  inspect(
    listing_sentence(
      {
        id: "x",
        name: "x",
        crossings: 0,
        whereabouts: InPort(departs=0),
        run: 0,
        officers: 0,
      },
      now=1000,
    ),
    content="In port at Kerala, leaving for Occitan any moment. Nobody aboard yet.",
  )
}

///|
test "the fleet list says where a ship is, and not who is aboard" {
  let l : @core.Listing = {
    id: "flea",
    name: "EF-287 The Flea on the Drum",
    crossings: 0,
    whereabouts: InPort(departs=600),
    run: 0,
    officers: 3,
  }
  assert_eq(
    fleet_sentence(l, now=0),
    "EF-287 The Flea on the Drum: In port at Kerala, leaving for Occitan in about 10 minutes.",
  )
  assert_false(fleet_sentence(l, now=0).contains("aboard"))
}

///|
test "leaving is after the voyage, and standing down is not leaving" {
  let p = @ships.profiles()[1]
  let s = @core.State::initial(p.ship(seed=1), profile=p.name).apply(
    Tick(at=1_800_000_000),
  ) catch {
    _ => panic()
  }
  let (_, s) = p.due(s, 1_800_000_600, officer=_ => true)
  let s = s.apply(Crew(crew="ann", intent=Posted(post=Drive))) catch {
    _ => panic()
  }
  debug_inspect(
    leaving_sentences(s, "ann"),
    content=(
      #|["You are aboard until the ship docks at Occitan, and may leave then."]
    ),
  )
  let s = s.apply(Crew(crew="ann", intent=Left)) catch { _ => panic() }
  debug_inspect(
    you_sentences(s, "ann"),
    content=(
      #|["You are standing down. Take a post to work."]
    ),
  )
  let s = s.apply(Crew(crew="ann", intent=Leaving(leaving=true))) catch {
    _ => panic()
  }
  debug_inspect(
    leaving_sentences(s, "ann"),
    content=(
      #|["You leave the ship when it docks at Occitan, and choose another then."]
    ),
  )
}

///|
/// The Tigress docked with a leg's stores to load and its hull at half,
/// "0" aboard on `post`.
fn launching(post : @core.Post?) -> @core.State {
  let p = @ships.fleet()[0].profile
  let s = @core.State::initial(
    { ..p.ship(seed=1), hull: @core.HULL_FULL / 2L, },
    profile=p.name,
  )
  let s : @core.State = {
    ..s,
    at: 1_800_000_000,
    leg: InPort(port={
      ..@core.Port::new(1_800_000_000, @ships.stores(legs=0)),
      ask: Some(Drive),
    }),
  }
  match post {
    Some(post) =>
      s.apply(Crew(crew="0", intent=Posted(post~))) catch {
        _ => panic()
      }
    None => s.apply(Crew(crew="0", intent=Signed)) catch { _ => panic() }
  }
}

///|
test "in port, the launch in sentences" {
  debug_inspect(
    where_sentences(launching(Some(Drive))),
    content=(
      #|[
      #|  "In port at Kerala, bound for Occitan, 15.7 light-years away.",
      #|  "Stores load in about 45 minutes, and the ship departs then.",
      #|  "The yard has the hull at 50%, and 60% by then.",
      #|]
    ),
  )
  debug_inspect(
    you_sentences(launching(Some(Drive)), "0"),
    content=(
      #|["You load stores on the drive, and take the drive when the ship departs."]
    ),
  )
  debug_inspect(
    you_sentences(launching(Some(Craft)), "0"),
    content=(
      #|["Crafts do nothing in port. You go to your craft when the ship departs."]
    ),
  )
  debug_inspect(
    port_ask_sentence(launching(None)),
    content=(
      #|["The ship asks for hands on the drive, to load stores."]
    ),
  )
}

///|
test "in port, a post says what it would do to the launch" {
  let posts : Array[@core.Post] = [Drive, Hull, Craft]
  debug_inspect(
    posts.map(p => port_effect(launching(None), "0", p)),
    content=(
      #|[
      #|  "departs 45 minutes sooner, hull 60% then",
      #|  "hull 88% at departure",
      #|  "nothing done in port",
      #|]
    ),
  )
  debug_inspect(
    posts.map(p => port_effect(launching(Some(Drive)), "0", p)),
    content=(
      #|[
      #|  "",
      #|  "departs 45 minutes later, hull 88% then",
      #|  "departs 45 minutes later, nothing done in port",
      #|]
    ),
  )
}

///|
test "an order for arrival reads as the post in port" {
  debug_inspect(
    order_sentence({ phase: Arrived, post: Hull, }),
    content=(
      #|"Standing order: the hull in port, from arrival."
    ),
  )
  debug_inspect(
    order_sentence({ phase: Coast, post: Drive, }),
    content=(
      #|"Standing order: the drive when the coast begins."
    ),
  )
}
