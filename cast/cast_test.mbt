///|
let config : String =
  #|{
  #|  "model": "fake:m",
  #|  "samples": 2,
  #|  "portrait": { "name": "portrait", "max_tokens": 100 },
  #|  "faces": [
  #|    { "name": "captain", "max_tokens": 100, "max_words": 500 },
  #|    { "name": "voyage", "max_tokens": 100, "model": "fake:other" }
  #|  ],
  #|  "banned": ["stars of destiny"]
  #|}

///|
let prompts : Array[(String, String)] = [
  ("setting.md", "SETTING\n"),
  ("portrait.system.md", "PORTRAIT TASK\n{% include \"setting.md\" %}"),
  (
    "portrait.user.md", "# cast entry\n\n{{ entry }}\n{% if notes %}\n# notes\n\n{{ notes }}\n{% endif %}",
  ),
  (
    "face.system.md", "FACE {{ face }}\n{% include \"faces/\" ~ face ~ \".md\" %}{% include \"setting.md\" %}",
  ),
  (
    "face.user.md", "# cast entry\n\n{{ entry }}\n\n# character\n\n{{ portrait }}\n",
  ),
  ("faces/captain.md", "captain task\n"),
  ("faces/voyage.md", "voyage task\n"),
]

///|
async fn write(path : String, text : String) -> Unit {
  @fs.write_file(path, text, create_mode=CreateOrTruncate)
}

///|
async fn read(path : String) -> String {
  @fs.read_file(path).text()
}

///|
/// A cast root with one ship, `HS-1`.
async fn fixture() -> String {
  let root = @fs.tmpdir(prefix="cast")
  @fs.mkdir("\{root}/prompts/faces", recursive=true)
  @fs.mkdir("\{root}/ships/HS-1", recursive=true)
  write("\{root}/cast.json", config)
  for p in prompts {
    write("\{root}/prompts/\{p.0}", p.1)
  }
  write("\{root}/ships/HS-1/entry.md", "ENTRY")
  root
}

///|
/// Replies with the first line of the system prompt, the sample and the user
/// prompt. Fails any call whose system prompt contains `fail`.
fn echo(models : Array[String]) -> @llm.Backend {
  @llm.Backend::new("echo", fn(c) raise {
    models.push(c.model)
    let head = c.system[0].split("\n").next().unwrap().to_owned()
    if c.system[0].contains("fail") {
      fail("refused")
    }
    {
      model: c.model,
      text: "\{head} #\{c.sample}|\{c.user}",
      reasoning: None,
      finish: Some("stop"),
      usage: @llm.Usage::zero(),
      raw: Json::null(),
    }
  })
}

///|
fn names(outcomes : Array[@cast.Outcome]) -> Array[String] {
  let names = outcomes.map(o => {
    match o {
      Drafted(d) => "drafted \{d.stage}.\{d.sample}"
      Failed(stage~, sample~, ..) => "failed \{stage}.\{sample}"
      Waiting(stage) => "waiting \{stage}"
    }
  })
  names.sort()
  names
}

///|
test "stages parse with optional fields absent" {
  let c : @cast.Config = @json.from_json(@json.parse(config))
  assert_eq(c.faces[0].max_words, Some(500))
  assert_eq(c.faces[1].max_words, None)
  assert_eq(c.faces[1].model, Some("fake:other"))
}

///|
async test "without a canon portrait, a ship gets portrait drafts and waits" {
  let root = fixture()
  write("\{root}/ships/HS-1/notes.md", "lean into the debt")
  let cast = @cast.Cast::load(root, echo([]))
  debug_inspect(
    names(cast.advance("HS-1")),
    content=(
      #|["waiting portrait", "drafted portrait.1", "drafted portrait.2"]
    ),
  )
  let draft = read("\{root}/ships/HS-1/drafts/portrait.2.md")
  inspect(
    draft,
    content=(
      #|PORTRAIT TASK #2|# cast entry
      #|
      #|ENTRY
      #|# notes
      #|
      #|lean into the debt
      #|
    ),
  )
  let record : @cast.Draft = @json.from_json(
    read("\{root}/ships/HS-1/drafts/portrait.2.json") |> @json.parse,
  )
  assert_eq(record.sample, 2)
  assert_eq(record.model, "fake:m")
  assert_eq(record.text_sha, @llm.sha256_hex(draft))
}

///|
async test "with a canon portrait, faces are drafted from it with their own model" {
  let root = fixture()
  let models = []
  let cast = @cast.Cast::load(root, echo(models))
  ignore(cast.advance("HS-1"))
  cast.approve("HS-1", "portrait", 1)
  models.clear()
  debug_inspect(
    names(cast.advance("HS-1")),
    content=(
      #|[
      #|  "drafted voyage.1",
      #|  "drafted voyage.2",
      #|  "drafted captain.1",
      #|  "drafted captain.2",
      #|]
    ),
  )
  models.sort()
  assert_eq(models, ["fake:m", "fake:m", "fake:other", "fake:other"])
  let portrait = read("\{root}/ships/HS-1/portrait.md")
  let captain = read("\{root}/ships/HS-1/drafts/captain.1.md")
  assert_true(captain.has_prefix("FACE captain #1|"))
  assert_true(captain.contains("# character\n\n\{portrait}"))
}

///|
async test "a face with a canon file is not drafted again" {
  let root = fixture()
  let cast = @cast.Cast::load(root, echo([]))
  ignore(cast.advance("HS-1"))
  cast.approve("HS-1", "portrait", 1)
  ignore(cast.advance("HS-1"))
  cast.approve("HS-1", "captain", 2)
  debug_inspect(
    names(cast.advance("HS-1")),
    content=(
      #|["drafted voyage.1", "drafted voyage.2"]
    ),
  )
}

///|
async test "a failed draft is reported and the others still run" {
  let root = fixture()
  write("\{root}/prompts/faces/voyage.md", "voyage task, fail\n")
  let cast = @cast.Cast::load(root, echo([]))
  ignore(cast.advance("HS-1"))
  cast.approve("HS-1", "portrait", 1)
  debug_inspect(
    names(cast.advance("HS-1")),
    content=(
      #|[
      #|  "failed voyage.1",
      #|  "failed voyage.2",
      #|  "drafted captain.1",
      #|  "drafted captain.2",
      #|]
    ),
  )
}

///|
async test "status tracks approval, hand edits and stale faces" {
  let root = fixture()
  let cast = @cast.Cast::load(root, echo([]))
  let ship = "\{root}/ships/HS-1"
  ignore(cast.advance("HS-1"))
  debug_inspect(
    cast.status("HS-1"),
    content=(
      #|[
      #|  { stage: "portrait", canon: Missing, drafts: 2 },
      #|  { stage: "captain", canon: Missing, drafts: 0 },
      #|  { stage: "voyage", canon: Missing, drafts: 0 },
      #|]
    ),
  )
  cast.approve("HS-1", "portrait", 2)
  ignore(cast.advance("HS-1"))
  cast.approve("HS-1", "captain", 1)
  write("\{ship}/captain.md", read("\{ship}/captain.md") + "a line by hand\n")
  debug_inspect(
    cast.status("HS-1"),
    content=(
      #|[
      #|  { stage: "portrait", canon: Approved(2), drafts: 2 },
      #|  { stage: "captain", canon: Edited(1), drafts: 2 },
      #|  { stage: "voyage", canon: Missing, drafts: 2 },
      #|]
    ),
  )
  // Approving another portrait leaves the captain built on the old one.
  cast.approve("HS-1", "portrait", 1)
  assert_true(cast.status("HS-1")[1].canon is Stale(_))
}

///|
test "clean strips a whole-reply fence and a leading file name line" {
  inspect(
    @cast.clean("voyage", "```markdown\nvoyage.md\n\nI carry.\n```\n"),
    content="I carry.\n",
  )
  inspect(@cast.clean("voyage", "I carry.\n"), content="I carry.\n")
  inspect(
    @cast.clean("captain", "# captain.md\n\nI carry.\n"),
    content="I carry.\n",
  )
  inspect(
    @cast.clean("captain", "# Captain\n\nI carry.\n"),
    content="I carry.\n",
  )
  inspect(
    @cast.clean("voice", "## Arriving\n\nHome.\n"),
    content="## Arriving\n\nHome.\n",
  )
}

///|
test "checks come from the stage" {
  let stage : @cast.Stage = {
    name: "voice",
    max_tokens: 1,
    model: None,
    temperature: None,
    max_words: Some(3),
    max_lines: Some(1),
    headings: Some(11),
  }
  debug_inspect(
    @cast.check(stage, ["stars of destiny"], "## one\nThe Stars of Destiny.\n"),
    content=(
      #|[
      #|  "mentions \"stars of destiny\"",
      #|  "has 6 words, wants at most 3",
      #|  "has 2 lines, wants at most 1",
      #|  "has 1 level-two headings, wants 11",
      #|]
    ),
  )
}
