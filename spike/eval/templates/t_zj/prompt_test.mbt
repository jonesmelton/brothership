///|
/// Markdown sources as a designer would author them on disk (trailing newline).
let sources : Map[String, String] = {
  "frame.md": (
    #|# task
    #|
    #|You are {{ ship }}, a sentient starship.
    #|
    #|{% include "setting.md" %}
    #|{% include "rules.md" %}
    #|{% if voyage %}
    #|{% include "voyage.md" %}
    #|{% endif %}
    #|# cast entry
    #|
    #|{{ cast_entry }}
    #|
    #|# relations
    #|
    #|{% for r in relations %}
    #|- {{ r.name }}: {{ r.bond }}
    #|{% endfor %}
  ),
  "setting.md": (
    #|# setting
    #|
    #|Liangshan Reach, 2731.
    #|
  ),
  "rules.md": (
    #|# rules
    #|
    #|- No FTL.
    #|- Delta-v is scarce.
    #|
  ),
  "voyage.md": (
    #|# voyage
    #|
    #|Burn for Ceres.
    #|
  ),
}

///|
let cast_entry : String =
  #|## Song Jiang
  #|
  #|- role: captain
  #|- temperament: *generous*, {{ not a tag }}
  #|
  #|> quoted line

///|
fn env() -> @zj.Environment {
  let env = @zj.Environment::new()
  env.set_loader(name => match sources.get(name) {
    Some(s) => Ok(s)
    None => Err("not found: \{name}")
  })
  env.set_options(
    @zj.RenderOptions::default()
    .with_whitespace_control(true, true)
    .with_strict_undefined(true),
  )
  env
}

///|
fn ctx(voyage : Bool) -> Json {
  {
    "ship": "Timely Rain",
    "voyage": Json::boolean(voyage),
    "cast_entry": Json::string(cast_entry),
    "relations": [
      { "name": "Wu Yong", "bond": "sworn" },
      { "name": "Li Kui", "bond": "protective" },
    ],
  }
}

///|
test "prompt with voyage" {
  let out = env().render("frame.md", ctx(true))
  assert_eq(
    out,
    (
      #|# task
      #|
      #|You are Timely Rain, a sentient starship.
      #|
      #|# setting
      #|
      #|Liangshan Reach, 2731.
      #|# rules
      #|
      #|- No FTL.
      #|- Delta-v is scarce.
      #|# voyage
      #|
      #|Burn for Ceres.
      #|# cast entry
      #|
      #|## Song Jiang
      #|
      #|- role: captain
      #|- temperament: *generous*, {{ not a tag }}
      #|
      #|> quoted line
      #|
      #|# relations
      #|
      #|- Wu Yong: sworn
      #|- Li Kui: protective
      #|
    ),
  )
}

///|
test "prompt without voyage" {
  let out = env().render("frame.md", ctx(false))
  inspect(out.contains("# voyage"), content="false")
  inspect(out.contains("Delta-v is scarce.\n# cast entry\n"), content="true")
}

///|
test "strict undefined" {
  let env = env()
  env.add_template("bad.md", "line one\n\n{{ shipp }}\n")
  try env.render("bad.md", ctx(true)) catch {
    err => {
      inspect(err.message(), content=(
        #|Template 'bad.md': Undefined value used in output
      ))
      inspect(err.diagnostic().span() is Some(_), content=(
        #|false
      ))
    }
  } noraise {
    s => fail("expected error, got \{s}")
  }
}
