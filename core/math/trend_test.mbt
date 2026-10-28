///|
test "per_hour rounds toward negative infinity" {
  inspect(@math.per_hour(10L, 3600L), content="10")
  inspect(@math.per_hour(1L, 3L), content="1200")
  inspect(@math.per_hour(1L, 7200L / 2L), content="1")
  inspect(@math.per_hour(1L, 3599L), content="1")
  inspect(@math.per_hour(-1L, 3599L), content="-2")
  inspect(@math.per_hour(-1L, 3600L), content="-1")
  inspect(@math.per_hour(-5L, 7L), content="-2572")
  inspect(@math.per_hour(5L, 7L), content="2571")
  inspect(@math.per_hour(0L, 17L), content="0")
}
