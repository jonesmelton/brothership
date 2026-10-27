///|
async test "propose validates, persists, and advances the snapshot" {
  let store = @store.Store::open(":memory:")
  defer store.close()
  debug_inspect(store.snapshot(), content="{ seq: 0, state: { clock: 0 } }")
  ignore(store.propose({ id: 1, event: Elapsed(ticks=2), }))
  debug_inspect(
    store.propose({ id: 2, event: Elapsed(ticks=3), }),
    content=(
      #|Accepted(id=2, snapshot={ seq: 2, state: { clock: 5 } })
    ),
  )
  debug_inspect(
    store.propose({ id: 3, event: Elapsed(ticks=0), }),
    content=(
      #|Refused(
      #|  id=3,
      #|  reason=NonPositiveTicks(ticks=0),
      #|  snapshot={ seq: 2, state: { clock: 5 } },
      #|)
    ),
  )
  debug_inspect(store.snapshot(), content="{ seq: 2, state: { clock: 5 } }")
}

///|
async test "reopening replays the log" {
  let dir = @fs.tmpdir(prefix="brothership-store-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/game.sqlite"
  let first = @store.Store::open(path)
  ignore(first.propose({ id: 1, event: Elapsed(ticks=4), }))
  ignore(first.propose({ id: 2, event: Elapsed(ticks=1), }))
  first.close()
  let second = @store.Store::open(path)
  defer second.close()
  debug_inspect(second.snapshot(), content="{ seq: 2, state: { clock: 5 } }")
}
