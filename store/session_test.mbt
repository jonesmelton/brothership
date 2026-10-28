///|
async test "a session reads back its officer after a reopen" {
  let dir = @fs.tmpdir(prefix="brothership-session-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/game.sqlite"
  let store = @store.Store::open(path)
  debug_inspect(store.session("token"), content="None")
  store.open_session("token", "officer-1", now=1_800_000_000)
  debug_inspect(store.session("token"), content="Some(\"officer-1\")")
  store.close()
  let reopened = @store.Store::open(path)
  defer reopened.close()
  debug_inspect(reopened.session("token"), content="Some(\"officer-1\")")
}
