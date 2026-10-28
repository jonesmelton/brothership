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
