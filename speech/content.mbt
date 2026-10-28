// Reading speech prompts, faces and the model key from disk.

///|
/// The Meta Model API key from `MODEL_API_KEY` or
/// `~/.config/brothership/meta-api.key`, if either is set.
pub async fn meta_key() -> String? {
  if @env.get_env_var("MODEL_API_KEY") is Some(key) && key != "" {
    return Some(key)
  }
  let home = @env.get_env_var("HOME").unwrap_or("")
  let path = "\{home}/.config/brothership/meta-api.key"
  guard @fs.exists(path) else { return None }
  Some(@fs.read_file(path).text().trim().to_owned())
}

///|
/// The prompts in `content`: the templates in `speech/`, the setting from
/// `cast/prompts/setting.md` and the gate's `gate/policy.md`.
pub async fn Speech::load(
  content~ : String,
  model~ : String,
  gate_model~ : String,
) -> Speech {
  let read = async fn(path : String) {
    @fs.read_file("\{content}/\{path}").text()
  }
  Speech::new(
    system=read("speech/system.md"),
    user=read("speech/user.md"),
    setting=read("cast/prompts/setting.md"),
    model~,
    gate=@llm_gate.Gate::new(model=gate_model, policy=read("gate/policy.md")),
  )
}

///|
/// A ship's faces from `content/cast/ships/<pennant>/`, if both
/// `captain.md` and `voice.md` are approved.
pub async fn Voice::load(content~ : String, title : @ships.Title) -> Voice? {
  let dir = "\{content}/cast/ships/\{title.pennant}"
  let captain = "\{dir}/captain.md"
  let voice = "\{dir}/voice.md"
  guard @fs.exists(captain) && @fs.exists(voice) else { return None }
  Some({
    epithet: title.epithet,
    captain: @fs.read_file(captain).text(),
    voice: @fs.read_file(voice).text(),
  })
}

///|
/// Meta Model API, routed by the `meta:` prefix, at most `limit` calls at
/// once, retried.
pub fn meta_backend(key : String, limit~ : Int32 = 4) -> @llm.Backend {
  let meta = @llm.Backend::openai_compatible(
    base_url="https://api.meta.ai/v1",
    api_key=key,
  )
  @llm.Backend::route(Map([("meta", meta)])).limited(limit).retrying()
}
