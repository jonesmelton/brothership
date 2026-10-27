///|
let sources : Map[String, String] = {
  "frame.md": (
    #|# task
    #|
    #|{% include "setting.md" %}
    #|{% if voyage %}
    #|Voyage on.
    #|{% endif %}
    #|# cast entry
    #|
    #|{{ entry }}
    #|
  ),
  "setting.md": (
    #|No FTL.
    #|
  ),
  "typo.md": "{{ entyr }}\n",
}

///|
test "renders includes, conditionals and multi-line values byte-exact" {
  let p = @prompt.Prompts::new(sources)
  let out = p.render("frame.md", {
    "voyage": false,
    "entry": "line 1\n\nline {{ 2 }}",
  })
  inspect(
    out,
    content=(
      #|# task
      #|
      #|No FTL.
      #|# cast entry
      #|
      #|line 1
      #|
      #|line {{ 2 }}
      #|
    ),
  )
}

///|
test "an undefined variable is an error naming the template and line" {
  let p = @prompt.Prompts::new(sources)
  let msg = try {
    ignore(p.render("typo.md", { "entry": "x" }))
    ""
  } catch {
    e => e.to_string()
  }
  assert_true(msg.contains("typo.md:1"))
  assert_true(msg.contains("{{ entyr }}"))
}
