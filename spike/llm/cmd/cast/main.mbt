// Runs layers 1 and 2 of the cast pipeline for every entry in `entries/`,
// writing `out/<pennant>/<file>.md`. Replies are cached in `cache/`, so a
// rerun only calls the model for changed inputs.
//
//   moon run cmd/cast             # call hyper on cache misses
//   moon run cmd/cast -- replay   # cache only; a miss is an error

///|
let model = "deepseek-v4.1-flash-1017"

///|
async fn read_dir(dir : String) -> Map[String, String] {
  let files = Map([])
  for name in @fs.readdir(dir, sort=true) {
    files[name] = @fs.read_file("\{dir}/\{name}").text()
  }
  files
}

///|
async fn main {
  let mode : @cache.Mode = if @env.args().contains("replay") {
    Replay
  } else {
    Live
  }
  let home = @env.get_env_var("HOME").unwrap()
  let api_key = @fs.read_file("\{home}/.config/brothership/hyper.key")
    .text()
    .trim()
    .to_owned()
  let hyper = @llm.Backend::openai_compatible(
    base_url="https://hyper.charm.land/v1",
    api_key~,
  )
  // Cache outside the limit, so hits don't wait for a slot.
  let backend = @cache.cached(hyper.limited(6), dir="cache", mode~)
  let p = @pipeline.Pipeline::new(
    backend,
    @prompt.Prompts::new(read_dir("prompts")),
    model~,
  )
  let ships = read_dir("entries")
    .iter()
    .map(kv => @pipeline.Ship::{
      pennant: kv.0.replace(old=".md", new=""),
      entry: kv.1,
    })
    .collect()
  let started = @env.now()
  @async.with_task_group(g => {
    for ship in ships {
      g.spawn_bg(() => {
        let files = p.ship(ship)
        @fs.mkdir("out/\{ship.pennant}", recursive=true, allow_exist=true)
        for f in files {
          @fs.write_file(
            "out/\{ship.pennant}/\{f.name}.md",
            f.text,
            create_mode=CreateOrTruncate,
          )
          let u = f.usage
          println(
            "\{ship.pennant}/\{f.name}.md in=\{u.input} out=\{u.output} (reasoning \{u.reasoning}) $\{u.cost_usd}",
          )
          for problem in f.problems {
            println("  ! \{problem}")
          }
        }
      })
    }
  })
  println("done in \{(@env.now() - started) / 1000}s")
}
