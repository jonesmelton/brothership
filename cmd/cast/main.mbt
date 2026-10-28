// Drives the cast pipeline over content/cast. Run from the repository root.
//
//   moon run cmd/cast -- run [pennant...]        draft what each ship is missing
//   moon run cmd/cast -- run --replay [pennant...]  cache only; a miss fails
//   moon run cmd/cast -- approve <pennant> <stage> <sample>
//   moon run cmd/cast -- status [pennant...]
//
// A pennant with no ship directory yet gets entry drafts from a seed built
// out of pennants.tsv, starting-cast.md and other ships' entries; approve
// one as its entry.md, then run again for the portrait. A pennant that is
// not in pennants.tsv at all fails in `run` rather than drafting an entry
// for a ship that does not exist.
//
// Replies are cached in .cache/llm, so rerunning only calls the model for
// prompts that changed. The Meta Model API key is read from MODEL_API_KEY,
// or else ~/.config/brothership/meta-api.key. Get one at dev.meta.ai.

///|
let root = "content/cast"

///|
async fn meta_key() -> String {
  if @env.get_env_var("MODEL_API_KEY") is Some(key) {
    return key
  }
  let home = @env.get_env_var("HOME").unwrap_or("")
  let path = "\{home}/.config/brothership/meta-api.key"
  guard @fs.exists(path) else {
    fail("set MODEL_API_KEY or write the key to \{path}")
  }
  @fs.read_file(path).text().trim().to_owned()
}

///|
async fn backend(mode : @cache.Mode) -> @llm.Backend {
  let providers = {
    "meta": @llm.Backend::openai_compatible(
      base_url="https://api.meta.ai/v1",
      api_key=if mode is Live { meta_key() } else { "" },
    ),
  }
  // Cache outside the limit, so cache hits don't wait for a slot; retry
  // inside the cache, so an incomplete reply is never stored.
  @cache.cached(
    @llm.Backend::route(providers).limited(6).retrying(),
    dir=".cache/llm",
    mode~,
  )
}

///|
async fn pennants(
  cast : @pipeline.Cast,
  given : Array[String],
) -> Array[String] {
  if given.length() > 0 {
    given
  } else {
    cast.ships()
  }
}

///|
async fn run(args : Array[String]) -> Unit {
  let mode : @cache.Mode = if args.contains("--replay") { Replay } else { Live }
  let cast = @pipeline.Cast::load(root, backend(mode))
  let ships = pennants(cast, args.filter(a => !a.has_prefix("--")))
  for ship in ships {
    guard cast.known(ship) else {
      fail("\{ship} is not in \{root}/pennants.tsv")
    }
  }
  let cost = Ref(0.0)
  @async.with_task_group(g => {
    for ship in ships {
      g.spawn_bg(() => {
        for outcome in cast.advance(ship) {
          match outcome {
            Drafted(d) => {
              let u = d.usage
              cost.val += u.cost_usd
              println(
                "\{ship} \{d.stage}.\{d.sample} in=\{u.input} out=\{u.output} reasoning=\{u.reasoning} $\{u.cost_usd}",
              )
              for problem in d.problems {
                println("  ! \{problem}")
              }
            }
            Failed(stage~, sample~, error~) =>
              println("\{ship} \{stage}.\{sample} FAILED: \{error}")
            Waiting(stage) => {
              let check = if stage == "entry" {
                "; check it against the novel before approving"
              } else {
                ""
              }
              println(
                "\{ship} waits for an approved \{stage}: approve \{ship} \{stage} <sample>\{check}",
              )
            }
          }
        }
      })
    }
  })
  // Cached replies report what they cost when first made.
  println("drafts cost $\{cost.val} to make, cache hits included")
}

///|
async fn status(args : Array[String]) -> Unit {
  let cast = @pipeline.Cast::load(root, backend(Replay))
  for ship in pennants(cast, args) {
    for s in cast.status(ship) {
      let canon = match s.canon {
        Missing => "-"
        Approved(n) => "approved \{n}"
        Edited(n) => "edited from \{n}"
        ByHand => "by hand"
        Stale(why) => "stale: \{why}"
      }
      println("\{ship}\t\{s.stage}\t\{canon}\t\{s.drafts} drafts")
    }
  }
}

///|
async fn main {
  let args = @env.args()[1:].to_owned()
  match args {
    ["run", .. rest] => run(rest.to_owned())
    ["approve", ship, stage, sample] => {
      let cast = @pipeline.Cast::load(root, backend(Replay))
      cast.approve(ship, stage, @string.parse_int(sample))
    }
    ["status", .. rest] => status(rest.to_owned())
    _ =>
      fail(
        "usage: run [--replay] [pennant...] | approve <pennant> <stage> <sample> | status [pennant...]",
      )
  }
}
