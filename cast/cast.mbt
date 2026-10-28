// The cast pipeline: each ship's entry becomes a private portrait, and the
// portrait becomes its faces, the files the running game reads. See
// docs/cast.md.

///|
/// One generated file and how to make it. Faces are listed in `cast.json`, so
/// adding one is a template and a line of config.
pub(all) struct Stage {
  name : String
  max_tokens : Int32
  /// `provider:model`; the config's `model` when absent.
  model : String?
  temperature : Double?
  /// Wire value passed to the provider (`low`, `high`, `xhigh`, ...).
  reasoning_effort : String?
  max_words : Int32?
  max_lines : Int32?
  /// Exact number of level-two headings.
  headings : Int32?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Config {
  model : String
  /// Drafts per stage per run.
  samples : Int32
  entry : Stage
  portrait : Stage
  faces : Array[Stage]
  /// Phrases no file may contain, matched case-insensitively.
  banned : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// The generation record of one draft, saved beside it as json. When a draft
/// is approved, its record moves into the ship's `record.json`.
pub(all) struct Draft {
  stage : String
  sample : Int32
  /// Key of the call in the reply cache.
  key : String
  model : String
  max_tokens : Int32
  temperature : Double?
  reasoning_effort : String?
  /// sha256 of each input file the draft was made from.
  inputs : Map[String, String]
  text_sha : String
  problems : Array[String]
  usage : @llm.Usage
  finish : String?
  /// The provider's response. Dropped from `record.json`.
  raw : Json
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum Outcome {
  Drafted(Draft)
  Failed(stage~ : String, sample~ : Int32, error~ : String)
  /// The stage needs a canon file before the ship can go further.
  Waiting(String)
} derive(Debug)

///|
pub(all) enum Canon {
  Missing
  /// The canon file is the named draft, unchanged.
  Approved(Int32)
  /// The canon file is the named draft, edited by hand.
  Edited(Int32)
  /// The canon file has no generation record, so it was written by hand.
  ByHand
  /// An input changed since the canon file was made.
  Stale(String)
} derive(Debug, Eq)

///|
pub(all) struct StageStatus {
  stage : String
  canon : Canon
  drafts : Int32
} derive(Debug, Eq)

///|
/// A cast directory: `cast.json`, `prompts/`, `pennants.tsv`,
/// `starting-cast.md`, and `ships/<pennant>/` holding `entry.md`, an
/// optional `notes.md`, canon files, `record.json` and `drafts/`. Drafts
/// are regenerated freely; canon files are only written by `approve`, or
/// by hand. A ship with no directory yet still drafts an entry: the draft
/// makes the directory.
pub struct Cast {
  priv root : String
  priv config : Config
  priv prompts : @prompt.Prompts
  priv backend : @llm.Backend
  /// Every ship in `pennants.tsv`, in file order. The seed an entry draft
  /// is made from is built from this, `starting-cast.md` and other entries.
  priv crew : Array[Crew]
  priv starting : String
}

///|
/// One row of `pennants.tsv`: a ship's pennant, Chinese conventional name
/// and English epithet.
pub(all) struct Crew {
  pennant : String
  conventional_name : String
  epithet : String
} derive(Debug, Eq)

///|
pub fn Crew::tier(self : Crew) -> String {
  if self.pennant.has_prefix("HS-") {
    "Heavenly Spirit"
  } else {
    "Earthly Fiend"
  }
}

///|
/// Parses one `pennants.tsv` row. The header and any short line give `None`.
pub fn crew(line : String) -> Crew? {
  let cols = line.split("\t").map(c => c.to_owned()).collect()
  if cols.length() < 3 || cols[0] == "pennant" {
    return None
  }
  Some({ pennant: cols[0], conventional_name: cols[1], epithet: cols[2], })
}

///|
/// The seed an entry draft is made from: what this repo already knows about
/// the ship, before the model fills the entry in from the source novel.
/// `starting` is the whole of `starting-cast.md`; `references` is every line
/// naming the pennant in other ships' entries.
pub fn seed(
  pennant~ : String,
  crew~ : Array[Crew],
  starting~ : String,
  references~ : Array[String],
) -> String {
  let mut found : Crew? = None
  for m in crew {
    if m.pennant == pennant {
      found = Some(m)
    }
  }
  let (epithet, heading) = match found {
    Some(m) => (m.epithet, "\{m.tier()} \{m.conventional_name}")
    None => (pennant, pennant)
  }
  let parts = ["## \{epithet}", heading]
  let note = starting_note(starting, pennant, epithet)
  if note != "" {
    parts.push("## starting cast\n\n\{note}")
  }
  if references.length() > 0 {
    parts.push("## in other ships' entries\n\n\{references.join("\n")}")
  }
  parts.join("\n\n") + "\n"
}

///|
/// The ship's section of `starting-cast.md`, without its heading.
fn starting_note(
  starting : String,
  pennant : String,
  epithet : String,
) -> String {
  let heading = "### \{pennant} \{epithet}"
  let out = []
  let mut on = false
  for line in starting.split("\n") {
    let line = line.to_owned()
    if line.has_prefix("#") {
      if on {
        break
      }
      on = line.has_prefix(heading)
    } else if on {
      out.push(line)
    }
  }
  out.join("\n").trim().to_owned()
}

///|
pub async fn Cast::load(root : String, backend : @llm.Backend) -> Cast {
  let config : Config = @json.from_json(
    @fs.read_file("\{root}/cast.json").json(),
  )
  let sources = Map([])
  read_tree("\{root}/prompts", "", sources)
  let members = []
  let pennants = @fs.read_file("\{root}/pennants.tsv").text()
  for line in pennants.split("\n") {
    match crew(line.to_owned()) {
      Some(m) => members.push(m)
      None => ()
    }
  }
  {
    root,
    config,
    prompts: @prompt.Prompts::new(sources),
    backend,
    crew: members,
    starting: read_or_empty("\{root}/starting-cast.md"),
  }
}

///|
async fn read_tree(
  dir : String,
  prefix : String,
  into : Map[String, String],
) -> Unit {
  for name in @fs.readdir(dir, sort=true) {
    let path = "\{dir}/\{name}"
    if @fs.kind(path) is Directory {
      read_tree(path, "\{prefix}\{name}/", into)
    } else {
      into["\{prefix}\{name}"] = @fs.read_file(path).text()
    }
  }
}

///|
pub async fn Cast::ships(self : Cast) -> Array[String] {
  @fs.readdir("\{self.root}/ships", sort=true)
}

///|
/// Whether the pennant names a ship in `pennants.tsv`.
pub fn Cast::known(self : Cast, pennant : String) -> Bool {
  self.crew.iter().any(m => m.pennant == pennant)
}

///|
fn Cast::dir(self : Cast, pennant : String) -> String {
  "\{self.root}/ships/\{pennant}"
}

///|
fn Cast::stages(self : Cast) -> Array[Stage] {
  [self.config.entry, self.config.portrait, ..self.config.faces]
}

///|
async fn read_or_empty(path : String) -> String {
  if @fs.exists(path) {
    @fs.read_file(path).text()
  } else {
    ""
  }
}

///|
/// Lines in other ships' entries that name this pennant, with their ship.
async fn Cast::references(self : Cast, pennant : String) -> Array[String] {
  let refs = []
  for other in self.ships() {
    if other == pennant {
      continue
    }
    let text = read_or_empty("\{self.dir(other)}/entry.md")
    for line in text.split("\n") {
      let line = line.to_owned()
      if line.contains(pennant) {
        refs.push(line.trim().to_owned())
      }
    }
  }
  refs
}

///|
/// Drafts the next stage the ship is missing: an entry until one is
/// approved, then portraits until one is approved, then every face without
/// a canon file. All drafts run concurrently; a failed draft is reported
/// and does not stop the others.
pub async fn Cast::advance(self : Cast, pennant : String) -> Array[Outcome] {
  let dir = self.dir(pennant)
  let outcomes = []
  let jobs : Array[(Stage, String, Map[String, String])] = []
  if !@fs.exists("\{dir}/entry.md") {
    let refs = self.references(pennant)
    let draft_seed = seed(
      pennant~,
      crew=self.crew,
      starting=self.starting,
      references=refs,
    )
    let roster = self.crew.map(m => "\{m.pennant} \{m.epithet}").join("\n")
    jobs.push(
      (self.config.entry, "entry", { "seed": draft_seed, "ships": roster }),
    )
  } else if !@fs.exists("\{dir}/portrait.md") {
    let entry = @fs.read_file("\{dir}/entry.md").text()
    let notes = read_or_empty("\{dir}/notes.md")
    jobs.push(
      (self.config.portrait, "portrait", { "entry": entry, "notes": notes }),
    )
  } else {
    let entry = @fs.read_file("\{dir}/entry.md").text()
    let portrait = @fs.read_file("\{dir}/portrait.md").text()
    for face in self.config.faces {
      if !@fs.exists("\{dir}/\{face.name}.md") {
        jobs.push((face, "face", { "entry": entry, "portrait": portrait }))
      }
    }
  }
  @async.with_task_group(g => {
    for job in jobs {
      let (stage, kind, inputs) = job
      for sample in 1..<=self.config.samples {
        g.spawn_bg(() => {
          outcomes.push(self.draft(dir, stage, kind, inputs, sample))
        })
      }
    }
  })
  if !@fs.exists("\{dir}/entry.md") {
    outcomes.push(Waiting("entry"))
  } else if !@fs.exists("\{dir}/portrait.md") {
    outcomes.push(Waiting("portrait"))
  }
  outcomes
}

///|
/// Renders `<kind>.system.md` and `<kind>.user.md` with the inputs, plus
/// `face` for faces, and writes `drafts/<stage>.<sample>.md` and its record.
async fn Cast::draft(
  self : Cast,
  dir : String,
  stage : Stage,
  kind : String,
  inputs : Map[String, String],
  sample : Int32,
) -> Outcome {
  try {
    let ctx : Map[String, Json] = Map([])
    for name, text in inputs {
      ctx[name] = Json::string(text)
    }
    if kind == "face" {
      ctx["face"] = Json::string(stage.name)
    }
    let call = @llm.Call::new(
      model=stage.model.unwrap_or(self.config.model),
      system=[self.prompts.render("\{kind}.system.md", Json::object(ctx))],
      user=self.prompts.render("\{kind}.user.md", Json::object(ctx)),
      max_tokens=stage.max_tokens,
      temperature?=stage.temperature,
      reasoning_effort?=stage.reasoning_effort,
      sample~,
    )
    let reply = self.backend.call(call)
    let text = clean(stage.name, reply.text)
    let draft : Draft = {
      stage: stage.name,
      sample,
      key: call.key(),
      model: call.model,
      max_tokens: call.max_tokens,
      temperature: call.temperature,
      reasoning_effort: call.reasoning_effort,
      inputs: inputs.map((_, text) => @llm.sha256_hex(text)),
      text_sha: @llm.sha256_hex(text),
      problems: check(stage, self.config.banned, text),
      usage: reply.usage,
      finish: reply.finish,
      raw: reply.raw,
    }
    let base = "\{dir}/drafts/\{stage.name}.\{sample}"
    @fs.mkdir("\{dir}/drafts", recursive=true, allow_exist=true)
    @fs.write_file("\{base}.md", text, create_mode=CreateOrTruncate)
    @fs.write_file(
      "\{base}.json",
      draft.to_json().stringify(indent=2),
      create_mode=CreateOrTruncate,
    )
    Drafted(draft)
  } catch {
    e => Failed(stage=stage.name, sample~, error=e.to_string())
  }
}

///|
async fn Cast::record(self : Cast, pennant : String) -> Map[String, Draft] {
  let path = "\{self.dir(pennant)}/record.json"
  if !@fs.exists(path) {
    return Map([])
  }
  @json.from_json(@fs.read_file(path).json())
}

///|
/// Makes a draft the canon file for its stage and records where it came from.
pub async fn Cast::approve(
  self : Cast,
  pennant : String,
  stage : String,
  sample : Int32,
) -> Unit {
  let dir = self.dir(pennant)
  let base = "\{dir}/drafts/\{stage}.\{sample}"
  guard @fs.exists("\{base}.md") else {
    fail("\{pennant} has no draft \{stage}.\{sample}")
  }
  let draft : Draft = @json.from_json(@fs.read_file("\{base}.json").json())
  let record = self.record(pennant)
  record[stage] = { ..draft, raw: Json::null(), }
  @fs.write_file(
    "\{dir}/\{stage}.md",
    @fs.read_file("\{base}.md").text(),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{dir}/record.json",
    Json(record).stringify(indent=2),
    create_mode=CreateOrTruncate,
  )
}

///|
pub async fn Cast::status(self : Cast, pennant : String) -> Array[StageStatus] {
  let dir = self.dir(pennant)
  let record = self.record(pennant)
  let drafts = if @fs.exists("\{dir}/drafts") {
    @fs.readdir("\{dir}/drafts")
  } else {
    []
  }
  // What each stage's inputs are now, to compare with what it was made from.
  let current = {
    "entry": @llm.sha256_hex(read_or_empty("\{dir}/entry.md")),
    "notes": @llm.sha256_hex(read_or_empty("\{dir}/notes.md")),
    "portrait": @llm.sha256_hex(read_or_empty("\{dir}/portrait.md")),
  }
  let statuses = []
  for stage in self.stages() {
    let path = "\{dir}/\{stage.name}.md"
    let canon = if !@fs.exists(path) {
      Missing
    } else if record.get(stage.name) is Some(made) {
      let changed = made.inputs
        .iter()
        .filter(kv => current.get(kv.0) is Some(sha) && sha != kv.1)
        .map(kv => kv.0)
        .collect()
      if changed.length() > 0 {
        Stale("\{changed.join(", ")} changed")
      } else if @llm.sha256_hex(@fs.read_file(path).text()) != made.text_sha {
        Edited(made.sample)
      } else {
        Approved(made.sample)
      }
    } else {
      ByHand
    }
    let count = drafts
      .filter(f => f.has_prefix("\{stage.name}.") && f.has_suffix(".md"))
      .length()
    statuses.push({ stage: stage.name, canon, drafts: count, })
  }
  statuses
}

///|
/// Strips a code fence around the whole reply and a leading line that is just
/// the file name, since models add both.
pub fn clean(name : String, text : String) -> String {
  let lines = text.trim_end().split("\n").map(l => l.to_owned()).collect()
  if lines.length() >= 2 &&
    lines[0].has_prefix("```") &&
    lines[lines.length() - 1] == "```" {
    lines.remove(lines.length() - 1) |> ignore
    lines.remove(0) |> ignore
  }
  if lines.length() > 0 && is_file_name(name, lines[0]) {
    lines.remove(0) |> ignore
  }
  while lines.length() > 0 && lines[0].trim() == "" {
    lines.remove(0) |> ignore
  }
  lines.join("\n") + "\n"
}

///|
/// `voice`, `voice.md`, `# voice.md` or `# Voice`: a line that only names the
/// file. Only a level-one heading counts, so a face's own `##` sections stay.
fn is_file_name(name : String, line : String) -> Bool {
  let bare = if line.has_prefix("# ") { line[2:].to_owned() } else { line }
  let bare = bare.trim().to_lower()
  bare == name || bare == "\{name}.md"
}

///|
/// Cheap checks, printed for a reviewer and never fatal.
pub fn check(
  stage : Stage,
  banned : Array[String],
  text : String,
) -> Array[String] {
  let problems = []
  let lower = text.to_lower()
  for phrase in banned {
    if lower.contains(phrase.to_lower()) {
      problems.push("mentions \"\{phrase}\"")
    }
  }
  if stage.max_words is Some(max) {
    let words = word_count(text)
    if words > max {
      problems.push("has \{words} words, wants at most \{max}")
    }
  }
  if stage.max_lines is Some(max) {
    let lines = text.split("\n").filter(l => l.trim() != "").count()
    if lines > max {
      problems.push("has \{lines} lines, wants at most \{max}")
    }
  }
  if stage.headings is Some(want) {
    let headings = text.split("\n").filter(l => l.has_prefix("## ")).count()
    if headings != want {
      problems.push("has \{headings} level-two headings, wants \{want}")
    }
  }
  problems
}

///|
fn word_count(text : String) -> Int32 {
  let mut n = 0
  let mut in_word = false
  for c in text {
    let space = c == ' ' || c == '\n' || c == '\t' || c == '\r'
    if !space && !in_word {
      n += 1
    }
    in_word = !space
  }
  n
}
