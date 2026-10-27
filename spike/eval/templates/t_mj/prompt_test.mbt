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
fn env() -> @minijinja.Environment {
  let env = @minijinja.Environment::new()
  env.set_loader(name => sources.get(name))
  env.set_trim_blocks(true)
  env.set_lstrip_blocks(true)
  env.set_keep_trailing_newline(true)
  env.set_undefined_behavior(Strict)
  env
}

///|
fn ctx(voyage : Bool) -> @minijinja.Value {
  @minijinja.Value::from_json({
    "ship": "Timely Rain",
    "voyage": Json::boolean(voyage),
    "cast_entry": Json::string(cast_entry),
    "relations": [
      { "name": "Wu Yong", "bond": "sworn" },
      { "name": "Li Kui", "bond": "protective" },
    ],
  })
}

///|
test "prompt with voyage" {
  let out = env().get_template("frame.md").render(ctx(true))
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
  let out = env().get_template("frame.md").render(ctx(false))
  inspect(out.contains("# voyage"), content="false")
  inspect(out.contains("Delta-v is scarce.\n# cast entry\n"), content="true")
}

///|
test "strict undefined errors with line" {
  let env = env()
  try
    env
    .template_from_named_str("bad.md", "line one\n\n{{ shipp }}\n")
    .render(ctx(true))
  catch {
    err => {
      inspect(err.line(), content="Some(3)")
      inspect(err, content=(
        #|undefined value (in bad.md:3)
      ))
    }
  } noraise {
    s => fail("expected error, got \{s}")
  }
}

///|
test "strict undefined in if" {
  try env().render_str("{% if nope %}x{% endif %}", ctx(true)) catch {
    err => inspect(err, content=(
      #|undefined value (in <string>:1)
    ))
  } noraise {
    s => fail("expected error, got \{s}")
  }
}

///|
test "missing include errors" {
  try env().render_str("{% include 'nope.md' %}", ctx(true)) catch {
    err => inspect(err, content=(
      #|template not found: tried to include non-existing template 'nope.md' (in <string>:1)
    ))
  } noraise {
    s => fail("expected error, got \{s}")
  }
}

///|
test "syntax error line" {
  try env().template_from_named_str("s.md", "a\nb\n{% if x %}\n") catch {
    err => inspect(err, content=(
      #|syntax error: unexpected end of input, expected end of block (in s.md:3)
    ))
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "debug info names the variable" {
  try
    env()
    .template_from_named_str("bad.md", "line one\n\n{{ crew.shipp }}\n")
    .render(ctx(true))
  catch {
    err => inspect(err.display_with_debug_info(), content=(
      #|undefined value (in bad.md:3)
      #|----------------------------------- bad.md ------------------------------------
      #|   1 | line one
      #|   2 | 
      #|   3 > {{ crew.shipp }}
      #|     i    ^^^^^^^^^^ undefined value
      #|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      #|No referenced variables
      #|-------------------------------------------------------------------------------
    ))
  } noraise {
    s => fail("expected error, got \{s}")
  }
}
