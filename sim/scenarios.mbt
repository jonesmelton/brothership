///|
const HOUR : Int64 = 3600L

///|
fn player(name : String, policy : Policy, joins_at~ : Int64 = 0L) -> Actor {
  { name, policy, cadence: Every(every=3L * HOUR, jitter=2L * HOUR), joins_at, }
}

///|
fn npc(name : String, policy : Policy) -> Actor {
  { name, policy, cadence: Reactive, joins_at: 0L, }
}

///|
/// An adversary that checks in every minute.
fn hammer(name : String, policy : Policy) -> Actor {
  { name, policy, cadence: Every(every=60L, jitter=0L), joins_at: 0L, }
}

///|
/// Starting points for the simulation page and the envelope tests.
pub fn scenarios() -> Array[Scenario] {
  let route = Route::default()
  let full = @core.HULL_FULL
  [
    {
      name: "solo player, NPC crew",
      route,
      hull: full,
      actors: [
        player("you", Cooperative),
        npc("npc 1", Careful),
        npc("npc 2", Careful),
        npc("npc 3", Cooperative),
        npc("npc 4", Selfish),
      ],
    },
    {
      name: "mixed crew of eight",
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
      route,
      hull: full,
      actors: Array::makei(8, i => player("p\{i + 1}", Selfish)),
    },
    {
      name: "late joiners",
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
      route,
      hull: full * 3L / 10L,
      actors: Array::makei(8, i => player("d\{i + 1}", Driver)),
    },
    {
      name: "hasteners every minute",
      route,
      hull: full,
      actors: Array::makei(8, i => hammer("h\{i + 1}", Hastener)),
    },
    {
      name: "saboteurs every minute",
      route,
      hull: full,
      actors: Array::makei(4, i => hammer("s\{i + 1}", Saboteur)) +
      Array::makei(4, i => player("p\{i + 1}", Cooperative)),
    },
  ]
}
