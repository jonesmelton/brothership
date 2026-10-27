///|
test "usage_of prices Muse Wonder at list rate" {
  let raw : Json = {
    "usage": {
      "prompt_tokens": 1_000_000,
      "completion_tokens": 1_000_000,
      "completion_tokens_details": { "reasoning_tokens": 250_000 },
    },
  }
  let u = usage_of("muse-wonder-1.0", raw)
  assert_eq(u.input, 1_000_000)
  assert_eq(u.output, 1_000_000)
  assert_eq(u.reasoning, 250_000)
  // $4 input + $20 output per million; reasoning is already in output.
  assert_eq(u.cost_usd, 24.0)
}

///|
test "usage_of prices Muse Spark and reports zero for unknown models" {
  let raw : Json = {
    "usage": { "prompt_tokens": 2_000_000, "completion_tokens": 1_000_000 },
  }
  assert_eq(usage_of("muse-spark-1.3", raw).cost_usd, 6.75)
  let unknown = usage_of("other-model", raw)
  assert_eq(unknown.cost_usd, 0.0)
  assert_eq(unknown.input, 2_000_000)
}

///|
test "usage_of tolerates a response without usage" {
  assert_eq(usage_of("muse-wonder-1.0", Json::null()), Usage::zero())
}
