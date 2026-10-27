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
test "cached prompt tokens are priced at the cached rate" {
  // One live contributor call: 15 prompt tokens, none cached, 25 completed
  // of which 15 were reasoning. $0.10/$0.20 per million.
  let live : Json = {
    "usage": {
      "completion_tokens": 25,
      "prompt_tokens": 15,
      "total_tokens": 40,
      "completion_tokens_details": { "reasoning_tokens": 15 },
      "prompt_tokens_details": { "cached_tokens": 0 },
    },
  }
  let u = usage_of("muse-spark-1.3-contributor", live)
  assert_eq(u.input, 15)
  assert_eq(u.output, 25)
  assert_eq(u.reasoning, 15)
  assert_eq(u.cost_usd, 15.0 * 0.10 / 1_000_000.0 + 25.0 * 0.20 / 1_000_000.0)
  // A fully cached million-token Wonder prompt costs the cached rate only.
  let warm : Json = {
    "usage": {
      "prompt_tokens": 1_000_000,
      "completion_tokens": 0,
      "prompt_tokens_details": { "cached_tokens": 1_000_000 },
    },
  }
  assert_eq(usage_of("muse-wonder-1.0", warm).cost_usd, 0.20)
}

///|
test "usage_of tolerates a response without usage" {
  assert_eq(usage_of("muse-wonder-1.0", Json::null()), Usage::zero())
}

///|
test "reasoning_of reads Groq's reasoning field as well as reasoning_content" {
  let groq : Json = {
    "choices": [{ "message": { "content": "{}", "reasoning": "think" } }],
  }
  assert_eq(reasoning_of(groq), Some("think"))
  let meta : Json = {
    "choices": [{ "message": { "reasoning_content": "think" } }],
  }
  assert_eq(reasoning_of(meta), Some("think"))
}
