// Checks messages against the content gate's policy. Run from the repository
// root.
//
//   moon run cmd/gate -- [--replay] [--model meta:model] [file...]
//
// With no files it checks every sample in content/gate/samples and fails if
// a verdict disagrees with the sample's directory, clean or violation.
// Replies are cached in .cache/llm. The Meta Model API key is read from
// MODEL_API_KEY, or else ~/.config/brothership/meta-api.key.

///|
let root = "content/gate"

///|
let default_model = "meta:muse-spark-1.3"

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
/// Milliseconds each uncached call took, by the call's user message.
async fn backend(
  mode : @cache.Mode,
  timings : Map[String, Int64],
) -> @llm.Backend {
  let meta = @llm.Backend::openai_compatible(
    base_url="https://api.meta.ai/v1",
    api_key=if mode is Live { meta_key() } else { "" },
  )
  let routed = @llm.Backend::route(Map([("meta", meta)]))
  let timed = @llm.Backend::new(routed.name, async fn(c) {
    let start = @async.now()
    let r = routed.call(c)
    timings[c.user] = @async.now() - start
    r
  })
  @cache.cached(timed.limited(8).retrying(), dir=".cache/llm", mode~)
}

///|
async fn samples() -> Array[String] {
  let files = []
  for label in ["clean", "violation"] {
    let dir = "\{root}/samples/\{label}"
    for name in @fs.readdir(dir, include_hidden=false, sort=true) {
      files.push("\{dir}/\{name}")
    }
  }
  files
}

///|
fn expected(path : String) -> @llm_gate.Verdict? {
  if path.contains("/samples/clean/") {
    Some(Clean)
  } else if path.contains("/samples/violation/") {
    Some(Violation(""))
  } else {
    None
  }
}

///|
async fn main {
  let args = @env.args()[1:].to_owned()
  let mode : @cache.Mode = if args.contains("--replay") { Replay } else { Live }
  let model = match args.search("--model") {
    Some(i) if i + 1 < args.length() => args[i + 1]
    _ => default_model
  }
  let given = args.filter(a => !a.has_prefix("--") && a != model)
  let files = if given.length() > 0 { given } else { samples() }
  let gate = @llm_gate.Gate::new(
    model~,
    policy=@fs.read_file("\{root}/policy.md").text(),
  )
  let timings = Map([])
  let b = backend(mode, timings)
  let lines : Array[String] = Array::make(files.length(), "")
  let wrong = Ref(0)
  @async.with_task_group(g => {
    for i, file in files {
      g.spawn_bg(() => {
        let text = @fs.read_file(file).text().trim().to_owned()
        let verdict = gate.check(b, text) catch {
          e => {
            wrong.val += 1
            lines[i] = "\{file}\tERROR\t\{e}"
            return
          }
        }
        let shown = match verdict {
          Clean => "clean"
          Violation(evidence) => "violation\t\{evidence}"
        }
        let mark = match (expected(file), verdict) {
          (Some(Clean), Violation(_)) | (Some(Violation(_)), Clean) => {
            wrong.val += 1
            "WRONG "
          }
          _ => ""
        }
        let took = match timings.get(@llm_gate.wrap(text)) {
          Some(ms) => "\{ms}ms"
          None => "cached"
        }
        lines[i] = "\{mark}\{file}\t\{took}\t\{shown}"
      })
    }
  })
  for line in lines {
    println(line)
  }
  if wrong.val > 0 {
    fail("\{wrong.val} of \{files.length()} wrong or failed")
  }
}
