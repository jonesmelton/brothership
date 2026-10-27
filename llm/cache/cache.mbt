///|
pub(all) enum Mode {
  /// Read the cache, call through on a miss and store the reply.
  Live
  /// Read the cache only; a miss raises. For tests and offline reruns.
  Replay
} derive(Debug, Eq)

///|
/// The key of a call that was not in the cache, in `Replay` mode.
pub(all) suberror Miss {
  Miss(String)
} derive(Debug)

///|
/// Content-addressed reply cache: `<dir>/<call key>.json` holds the call and
/// its reply. A rerun of a pipeline skips every call whose inputs are
/// unchanged, so resuming after a failure is free.
pub fn cached(
  inner : @llm.Backend,
  dir~ : String,
  mode~ : Mode = Live,
) -> @llm.Backend {
  @llm.Backend::new("cached(\{inner.name})", async fn(c) {
    let key = c.key()
    let path = "\{dir}/\{key}.json"
    if @fs.exists(path) {
      match @fs.read_file(path).json() {
        { "reply": reply, .. } => return @json.from_json(reply)
        _ => fail("malformed cache entry \{path}")
      }
    }
    if mode is Replay {
      raise Miss(key)
    }
    let reply = inner.call(c)
    let entry : Json = { "call": c.to_json(), "reply": reply.to_json() }
    @fs.mkdir(dir, recursive=true, allow_exist=true)
    // Write then rename, so a crash never leaves a truncated entry.
    let tmp = "\{path}.tmp"
    @fs.write_file(tmp, entry.stringify(indent=2), create_mode=CreateOrTruncate)
    @fs.rename(tmp, path, replace=true)
    reply
  })
}
