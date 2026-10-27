///|
pub(all) struct Ship {
  pennant : String
  entry : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct File {
  name : String
  text : String
  /// Cheap-check findings. Printed for a reviewer, never fatal.
  problems : Array[String]
  usage : @llm.Usage
} derive(Debug, Eq, ToJson)

///|
/// Layers 1 and 2 of the liveship cast pipeline: a cast entry becomes a
/// third-person character, and the character becomes three first-person
/// sheets, generated independently and concurrently.
pub struct Pipeline {
  priv backend : @llm.Backend
  priv prompts : @prompt.Prompts
  priv model : String
  priv max_tokens : Int32
}

///|
pub fn Pipeline::new(
  backend : @llm.Backend,
  prompts : @prompt.Prompts,
  model~ : String,
  max_tokens~ : Int32 = 16000,
) -> Pipeline {
  { backend, prompts, model, max_tokens, }
}

///|
pub let sheets : Array[String] = ["self", "command", "voice"]

///|
/// Renders `<stage>.system.md` and `<stage>.user.md` with `ctx` and runs them.
async fn Pipeline::run(
  self : Pipeline,
  stage : String,
  name : String,
  ctx : Json,
) -> File {
  let call = @llm.Call::new(
    model=self.model,
    system=[self.prompts.render("\{stage}.system.md", ctx)],
    user=self.prompts.render("\{stage}.user.md", ctx),
    max_tokens=self.max_tokens,
  )
  let reply = self.backend.call(call)
  let text = clean(name, reply.text)
  { name, text, problems: check(name, text), usage: reply.usage, }
}

///|
/// The character followed by the sheets, in `sheets` order.
pub async fn Pipeline::ship(self : Pipeline, ship : Ship) -> Array[File] {
  let character = self.run("character", "character", { "entry": ship.entry })
  let files = [character]
  @async.with_task_group(g => {
    let tasks = sheets.map(sheet => {
      g.spawn(() => {
        self.run("sheet", sheet, {
          "sheet": sheet,
          "entry": ship.entry,
          "character": character.text,
        })
      })
    })
    for t in tasks {
      files.push(t.wait())
    }
  })
  files
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
  if lines.length() > 0 &&
    (lines[0].trim() == name || lines[0].trim() == "\{name}.md") {
    lines.remove(0) |> ignore
  }
  while lines.length() > 0 && lines[0].trim() == "" {
    lines.remove(0) |> ignore
  }
  lines.join("\n") + "\n"
}

///|
pub fn check(name : String, text : String) -> Array[String] {
  let problems = []
  let lower = text.to_lower()
  for phrase in ["stars of destiny", "water margin"] {
    if lower.contains(phrase) {
      problems.push("mentions \"\{phrase}\"")
    }
  }
  let words = word_count(text)
  let lines = text.split("\n").filter(l => l.trim() != "").count()
  match name {
    "self" => {
      if lines > 15 {
        problems.push("has \{lines} lines, wants at most 15")
      }
      if words > 200 {
        problems.push("has \{words} words, wants at most 200")
      }
    }
    "command" =>
      if words > 400 {
        problems.push("has \{words} words, wants at most 400")
      }
    "voice" => {
      let headings = text.split("\n").filter(l => l.has_prefix("## ")).count()
      if headings != 11 {
        problems.push("has \{headings} level-two headings, wants 11")
      }
    }
    _ => ()
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
