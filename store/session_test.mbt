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

///|
async test "officers lists every session's officer, newest first" {
  let store = @store.Store::open(":memory:")
  defer store.close()
  store.open_session("a", "OF-A", now=1_800_000_000)
  store.open_session("b", "OF-B", now=1_800_000_100)
  debug_inspect(
    store.officers(),
    content=(
      #|[("OF-B", 1800000100), ("OF-A", 1800000000)]
    ),
  )
}
