///|
/// Prompt templates, rendered with minijinja. Undefined variables are errors,
/// and block tags leave no blank lines, so markdown renders as written.
pub struct Prompts {
  priv env : @minijinja.Environment
}

///|
/// `sources` maps a template name, as used in `render` and `{% include %}`,
/// to its text.
pub fn Prompts::new(sources : Map[String, String]) -> Prompts {
  let env = @minijinja.Environment::new()
  env.set_loader(name => sources.get(name))
  env.set_trim_blocks(true)
  env.set_lstrip_blocks(true)
  env.set_keep_trailing_newline(true)
  env.set_undefined_behavior(Strict)
  { env, }
}

///|
pub(all) suberror PromptError {
  PromptError(String)
} derive(Debug)

///|
pub impl Show for PromptError with fn output(self, logger) {
  let PromptError(msg) = self
  logger.write_string(msg)
}

///|
/// Errors carry minijinja's source excerpt, since its message alone does not
/// name the undefined variable.
pub fn Prompts::render(
  self : Prompts,
  name : String,
  ctx : Json,
) -> String raise PromptError {
  self.env.get_template(name).render(@minijinja.Value::from_json(ctx)) catch {
    e => raise PromptError(e.display_with_debug_info())
  }
}
