///|
fn service_character(ch : Char) -> Bool {
  for c in SERVICE_ALPHABET {
    if c == ch {
      return true
    }
  }
  false
}

///|
test "a service number is readable and uses no ambiguous characters" {
  for _ in 0..<200 {
    let id = new_officer()
    assert_true(id.has_prefix("OF-"))
    assert_eq(id.length(), 10)
    for i in 3..<id.length() {
      let ch = id.get_char(i).unwrap()
      assert_true(
        service_character(ch),
        msg="service number has an unknown character: \{id}",
      )
      assert_false(
        ch == 'I' || ch == 'L' || ch == 'O' || ch == 'U',
        msg="service number has an ambiguous character: \{id}",
      )
    }
  }
}

///|
test "the session cookie is Secure in production and not in development" {
  inspect(
    session_cookie("token", secure=true).contains("; Secure"),
    content="true",
  )
  inspect(
    session_cookie("token", secure=false).contains("; Secure"),
    content="false",
  )
  inspect(
    session_cookie("token", secure=true),
    content=(
      #|session=token; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000; Secure
    ),
  )
}
