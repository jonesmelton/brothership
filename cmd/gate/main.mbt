// Checks messages against the content gate's policy. Run from the repository
// root.
//
//   moon run cmd/gate -- [--replay] [file...]
//
// With no files it checks every sample in content/gate/samples and fails if
// a verdict disagrees with the sample's directory, clean or violation.
// Replies are cached in .cache/llm. The Groq key is read from GROQ_API_KEY,
// or else ~/.config/brothership/groq.key.

///|
let root = "content/gate"

///|
let model = "groq:openai/gpt-oss-safeguard-20b"

///|
async fn groq_key() -> String {
  if @env.get_env_var("GROQ_API_KEY") is Some(key) {
    return key
  }
  let home = @env.get_env_var("HOME").unwrap_or("")
  let path = "\{home}/.config/brothership/groq.key"
  guard @fs.exists(path) else {
    fail("set GROQ_API_KEY or write the key to \{path}")
  }
  @fs.read_file(path).text().trim().to_owned()
}

///|
async fn backend(mode : @cache.Mode) -> @llm.Backend {
  let providers = {
    "groq": @llm.Backend::openai_compatible(
      base_url="https://api.groq.com/openai/v1",
      api_key=if mode is Live { groq_key() } else { "" },
    ),
  }
  @cache.cached(
    @llm.Backend::route(providers).limited(8).retrying(),
    dir=".cache/llm",
    mode~,
  )
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
  let given = args.filter(a => !a.has_prefix("--"))
  let files = if given.length() > 0 { given } else { samples() }
  let gate = @llm_gate.Gate::new(
    model~,
    policy=@fs.read_file("\{root}/policy.md").text(),
  )
  let b = backend(mode)
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
        lines[i] = "\{mark}\{file}\t\{shown}"
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
