///|
const HOUR : Int64 = 3600L

///|
fn player(
  name : String,
  policy : Policy,
  craft~ : @core.Craft = Artist,
  joins_at~ : Int64 = 0L,
) -> Actor {
  {
    name,
    policy,
    craft,
    cadence: Every(every=3L * HOUR, jitter=2L * HOUR),
    joins_at,
  }
}

///|
fn npc(name : String, policy : Policy) -> Actor {
  { name, policy, craft: Artist, cadence: Reactive, joins_at: 0L, }
}

///|
/// An adversary that checks in every minute.
fn hammer(name : String, policy : Policy) -> Actor {
  {
    name,
    policy,
    craft: Artist,
    cadence: Every(every=60L, jitter=0L),
    joins_at: 0L,
  }
}

///|
/// Starting points for the simulation page and the envelope tests.
pub fn scenarios() -> Array[Scenario] {
  let ship = Profile::default()
  let route = ship.route
  let full = @core.HULL_FULL
  [
    {
      name: "solo player, NPC crew",
      ship,
      route,
      hull: full,
      actors: [
        player("you", Cooperative),
        npc("npc 1", Careful),
        npc("npc 2", Steady),
      ],
    },
    {
      name: "mixed crew of eight",
      ship,
      route,
      hull: full,
      actors: [
        player("a", Cooperative),
        player("b", Cooperative),
        player("c", Careful),
        player("d", Careful),
        player("e", Selfish),
        player("f", Selfish),
        player("g", Random),
        player("h", Driver),
        npc("npc 1", Careful),
        npc("npc 2", Careful),
      ],
    },
    {
      name: "everyone selfish",
      ship,
      route,
      hull: full,
      actors: Array::makei(8, i => player("p\{i + 1}", Selfish)),
    },
    {
      name: "late joiners",
      ship,
      route,
      hull: full,
      actors: [player("a", Cooperative), player("b", Careful)] +
      Array::makei(6, i => {
        player(
          "late \{i + 1}",
          Cooperative,
          joins_at=(i + 1).to_int64() * HOUR * 4L / 3L,
        )
      }),
    },
    {
      name: "drivers on a worn hull",
      ship,
      route,
      hull: full * 3L / 10L,
      actors: Array::makei(8, i => player("d\{i + 1}", Driver)),
    },
    {
      name: "hasteners every minute",
      ship,
      route,
      hull: full,
      actors: Array::makei(8, i => hammer("h\{i + 1}", Hastener)),
    },
    {
      name: "saboteurs every minute",
      ship,
      route,
      hull: full,
      actors: Array::makei(4, i => hammer("s\{i + 1}", Saboteur)) +
      Array::makei(4, i => player("p\{i + 1}", Cooperative)),
    },
  ]
}
