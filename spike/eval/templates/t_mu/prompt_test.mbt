///|
let frame : String =
  #|# task
  #|
  #|You are {{ship}}, a sentient starship.
  #|
  #|{{> setting}}
  #|{{> rules}}
  #|{{#voyage}}
  #|{{> voyage}}
  #|{{/voyage}}
  #|# cast entry
  #|
  #|{{{cast_entry}}}
  #|
  #|# relations
  #|
  #|{{#relations}}
  #|- {{name}}: {{bond}}
  #|{{/relations}}

///|
let partials : Map[String, String] = {
  "setting": (
    #|# setting
    #|
    #|Liangshan Reach, 2731.
    #|
  ),
  "rules": (
    #|# rules
    #|
    #|- No FTL.
    #|- Delta-v is scarce.
    #|
  ),
  "voyage": (
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
  let out = @mustache.render_string(frame, ctx(true), partials~)
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
  let out = @mustache.render_string(frame, ctx(false), partials~)
  inspect(out.contains("# voyage"), content="false")
  inspect(out.contains("Delta-v is scarce.\n# cast entry\n"), content="true")
}

///|
test "double-brace escapes markdown" {
  inspect(
    @mustache.render_string("{{x}}", { "x": "> a & b" }),
    content="&gt; a &amp; b",
  )
}

///|
test "missing variable is silent" {
  inspect(@mustache.render_string("[{{shipp}}]", ctx(true)), content="[]")
}

///|
fn attempt(f : () -> String raise) -> Result[String, Error] {
  try Ok(f()) catch {
    e => Err(e)
  }
}

///|
test "missing partial" {
  inspect(
    attempt(() => @mustache.render_string("[{{> nope}}]", ctx(true), partials~)),
    content=(
      #|Ok([])
    ),
  )
  inspect(
    attempt(() => @mustache.render_string_with_options(
      "[{{> nope}}]",
      ctx(true),
      partials,
      @mustache.RenderOptions::new(missing_partial_is_error=true),
    )),
    content=(
      #|Err(RenderError: Missing partial: nope)
    ),
  )
}

///|
test "syntax error message" {
  inspect(
    attempt(() => @mustache.render_string("a\nb\n{{#x}}\n", ctx(true))),
    content=(
      #|Err(ParseError: Unclosed section: x)
    ),
  )
  inspect(attempt(() => @mustache.render_string("a\n{{/x}}\n", ctx(true))), content=(
    #|Err(ParseError: Unexpected section end tag: /x)
  ))
}
