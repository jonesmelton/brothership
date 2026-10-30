///|
test "a key spends its burst, then waits for one token per interval" {
  let limiter = Limiter::new(burst=3, interval=10)
  inspect(limiter.take("a", now=100), content="0")
  inspect(limiter.take("a", now=100), content="0")
  inspect(limiter.take("a", now=100), content="0")
  inspect(limiter.take("a", now=100), content="10")
  inspect(limiter.take("a", now=104), content="6")
  inspect(limiter.take("a", now=110), content="0")
  inspect(limiter.take("a", now=110), content="10")
}

///|
test "a refused take costs nothing and keys do not share tokens" {
  let limiter = Limiter::new(burst=1, interval=10)
  inspect(limiter.take("a", now=0), content="0")
  for _ in 0..<100 {
    inspect(limiter.take("a", now=1), content="9")
  }
  inspect(limiter.take("a", now=10), content="0")
  inspect(limiter.take("b", now=1), content="0")
}

///|
test "recovered keys are swept once many are held" {
  let limiter = Limiter::new(burst=1, interval=1)
  for i in 0..<SWEEP_AT {
    limiter.take("k\{i}", now=0) |> ignore
  }
  inspect(limiter.next.length(), content="4096")
  limiter.take("late", now=100) |> ignore
  inspect(limiter.next.length(), content="1")
}
