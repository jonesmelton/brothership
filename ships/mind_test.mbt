///|
/// A state just departed on profile `p`'s first hop, with nobody aboard.
/// "a" has regard enough for a promotion.
fn departed(p : @ships.Profile) -> (@core.State, Int64) {
  let ship = p.ship(seed=1)
  let records : Map[String, @core.Record] = {
    "a": { regard: 200L * @core.REGARD_HOUR, works: 0, carry: 0, rank: Some(0L) },
  }
  let mut s = @core.State::initial({ ..ship, records, }, profile=p.name)
  let mut now = 1_800_000_000L
  while !(s.leg is Underway(..)) {
    let (_, next) = p.due(s, now, officer=_ => true)
    s = next
    now = p.wake(s).max(now + 1L)
  }
  (s, now)
}

///|
test "a minded ship leaves its asks and refits to its mind" {
  let p = @ships.profiles()[1]
  let (s, now) = departed(p)
  let s = { ..s, leg: Underway(crossing=s.crossing().unwrap(), spoke=None) }
  let (events, _) = p.due(s, now + 1L, officer=_ => true, minded=true)
  debug_inspect(events, content="[Tick(at=1800000602)]")
  let (scripted, _) = p.due(s, now + 1L, officer=_ => true)
  inspect(scripted.length() > 1, content="true")
}

///|
test "a minded ship waits for its mind at arrival, then promotes by script" {
  let p = @ships.profiles()[1]
  let (s, _) = departed(p)
  let s = s.apply(Crew(crew="a", intent=Posted(post=Drive))) catch {
    _ => panic()
  }
  let mut s = s
  let mut now = s.at
  while s.crossing().unwrap().arrived_at is None {
    now = p.wake(s).max(now + 1L)
    let (_, next) = p.due(s, now, officer=_ => true, minded=true)
    s = next
  }
  let arrived = now
  inspect(p.wake(s, minded=true), content="\{arrived + @ships.MIND_WAIT}")
  let (early, _) = p.due(
    s,
    arrived + @ships.MIND_WAIT - 1L,
    officer=_ => true,
    minded=true,
  )
  inspect(early.contains(Docked), content="false")
  let (late, _) = p.due(
    s,
    arrived + @ships.MIND_WAIT,
    officer=_ => true,
    minded=true,
  )
  inspect(late.contains(Docked), content="true")
  inspect(late.contains(Promoted(crew="a", rank=1)), content="true")
}

///|
test "a mind's promotions keep to one step, the hands aboard and the caps" {
  let p = @ships.profiles()[1]
  let c = @core.Crossing::new(p.next_plan(legs=0, coils=0), p.ship(seed=1))
  let hand = (rank : Int64) => {
    @core.Hand::{
      post: Drive,
      craft: Artist,
      rank,
      watch: None,
      order: None,
    }
  }
  let c = {
    ..c,
    phase: Arrived,
    hands: {
      "a": hand(3),
      "b": hand(3),
      "c": hand(2),
      "d": hand(0),
      "e": hand(1),
    },
  }
  debug_inspect(
    @ships.allowed(c, ["d", "a", "b", "c", "ghost", "d"], officer=_ => true),
    content=(
      #|[("d", 1), ("a", 4), ("c", 3)]
    ),
  )
  debug_inspect(
    @ships.allowed(c, ["e"], officer=id => id != "e"),
    content="[]",
  )
}
