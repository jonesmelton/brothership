///|
let sources : Map[String, String] = {
  "setting.md": "SETTING\n",
  "world.md": "WORLD\n",
  "character.system.md": "CHARACTER TASK\n{% include \"setting.md\" %}{% include \"world.md\" %}",
  "character.user.md": "# cast entry\n\n{{ entry }}\n",
  "sheet.system.md": "SHEET {{ sheet }}\n{% include \"setting.md\" %}{% include \"world.md\" %}",
  "sheet.user.md": "# cast entry\n\n{{ entry }}\n\n# character\n\n{{ character }}\n",
}

///|
/// Replies with the first line of the system prompt and the user prompt,
/// and records the peak number of calls in flight.
fn echo(peak : Ref[Int32]) -> @llm.Backend {
  let in_flight = Ref(0)
  @llm.Backend::new("echo", async fn(c) {
    in_flight.val += 1
    peak.val = @cmp.maximum(peak.val, in_flight.val)
    @async.sleep(5)
    in_flight.val -= 1
    let head = c.system[0].split("\n").next().unwrap().to_owned()
    {
      model: c.model,
      text: "\{head}|\{c.user}",
      reasoning: None,
      usage: @llm.Usage::zero(),
    }
  })
}

///|
fn pipeline(backend : @llm.Backend) -> @pipeline.Pipeline {
  @pipeline.Pipeline::new(backend, @prompt.Prompts::new(sources), model="m")
}

///|
async test "a ship yields the character then three sheets built from it" {
  let ship = @pipeline.Ship::{ pennant: "HS-367", entry: "ENTRY", }
  let files = pipeline(echo(Ref(0))).ship(ship)
  debug_inspect(
    files.map(f => f.name),
    content=(
      #|["character", "self", "command", "voice"]

    ),
  )
  inspect(files[0].text, content="CHARACTER TASK|# cast entry\n\nENTRY\n")
  assert_true(files[1].text.has_prefix("SHEET self|"))
  // Every sheet sees the character's text.
  for f in files[1:] {
    assert_true(f.text.contains("# character\n\nCHARACTER TASK|"))
  }
}

///|
async test "the three sheets run concurrently" {
  let peak = Ref(0)
  ignore(pipeline(echo(peak)).ship({ pennant: "HS-367", entry: "ENTRY", }))
  assert_eq(peak.val, 3)
}

///|
test "clean strips a whole-reply fence and a leading file name line" {
  inspect(
    @pipeline.clean("self.md", "```markdown\nself.md\n\nI carry.\n```\n"),
    content="I carry.\n",
  )
  inspect(@pipeline.clean("self.md", "I carry.\n"), content="I carry.\n")
}

///|
test "checks flag leaks and sheet shape" {
  inspect(
    @pipeline.check("voice", "## one\nThe stars of destiny.\n"),
    content=(
      #|[mentions "stars of destiny", has 1 level-two headings, wants 11]
    ),
  )
  inspect(@pipeline.check("self", "a b c\n"), content="[]")
  let long = Array::make(201, "word").join(" ")
  inspect(
    @pipeline.check("self", long),
    content=(
      #|[has 201 words, wants at most 200]
    ),
  )
}
