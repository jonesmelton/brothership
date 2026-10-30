///|
/// A Tigress crossing with `ann` on the hull and `bo` on the drive, two
/// hours in, and the ship's records giving them ranks.
fn underway() -> (@core.State, Array[@core.Entry]) {
  let p = @ships.profiles()[1]
  let mut ship = p.ship(seed=1)
  let records = ship.records.copy()
  records["ann"] = { regard: 0, works: 0, carry: 0, rank: Some(3L), served: 0, }
  records["bo"] = { regard: 0, works: 0, carry: 0, rank: Some(2L), served: 0, }
  ship = { ..ship, records, }
  let mut c = @core.Crossing::new(p.next_plan(legs=0, coils=0), ship)
  c = c.apply(Posted(crew="ann", post=Hull)) catch { _ => panic() }
  c = c.apply(Posted(crew="bo", post=Drive)) catch { _ => panic() }
  c = c.apply(Elapsed(ticks=7200)) catch { _ => panic() }
  let at = 1_800_000_000L
  let officers : Map[String, @core.Officer] = {
    "ann": { post: Some(Hull), leaving: false, active: true, },
    "bo": { post: Some(Drive), leaving: false, active: true, },
  }
  let entries : Array[@core.Entry] = [
    { seq: 1, at: at - 900L, happening: Took(crew="bo", post=Drive), },
    { seq: 2, at: at - 600L, happening: Stood(crew="ann"), },
  ]
  (
    {
      at,
      profile: p.name,
      ship,
      leg: Underway(crossing=c, spoke=None),
      officers,
    },
    entries,
  )
}

///|
test "the roster is you first, then by rank, with the longest post" {
  let (s, entries) = underway()
  let rows = roster_rows(s, entries, you="ann", ship="The Tigress")
  assert_eq(rows.length(), 2)
  assert_true(rows[0].you)
  assert_eq(rows[0].crew, "ann")
  assert_eq(rows[0].rank, 3L)
  assert_eq(rows[0].longest, Some((Hull, 2L)))
  assert_eq(rows[1].crew, "bo")
  assert_eq(rows[1].longest, Some((Drive, 2L)))
  assert_eq(
    duty_sentence(rows[0], s),
    "On the hull. 2 hours there this crossing.",
  )
  // A viewer who is not aboard sees the same crew by rank.
  let by_rank = roster_rows(s, entries, you="nobody", ship="The Tigress")
  assert_eq(by_rank.map(r => r.crew), ["ann", "bo"])
  // The viewer is first even below another's rank.
  let bo = roster_rows(s, entries, you="bo", ship="The Tigress")
  assert_eq(bo.map(r => r.crew), ["bo", "ann"])
}

///|
test "the roster names an officer's last action by service number" {
  let (s, entries) = underway()
  let rows = roster_rows(s, entries, you="ann", ship="The Tigress")
  match rows[1].last {
    Some((line, _)) => assert_eq(line, "bo took the drive.")
    None => fail("bo has no last action")
  }
  match rows[0].last {
    Some((line, _)) => assert_eq(line, "You stood your watch to its end.")
    None => fail("ann has no last action")
  }
}

///|
test "in port the roster names the post each officer will take" {
  let p = @ships.profiles()[1]
  let s = @core.State::initial(p.ship(seed=1), profile=p.name).apply(
    Tick(at=1_800_000_000L),
  ) catch {
    _ => panic()
  }
  let s = s.apply(Crew(crew="ann", intent=Posted(post=Hull))) catch {
    _ => panic()
  }
  let rows = roster_rows(s, [], you="ann", ship="The Tigress")
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].post, Some(Hull))
  assert_eq(rows[0].longest, None)
  assert_eq(
    duty_sentence(rows[0], s),
    "In port, to take the hull at departure.",
  )
}
