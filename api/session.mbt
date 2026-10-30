///|
/// How long a session cookie lives, in seconds: 30 days.
const SESSION_MAX_AGE : Int64 = 2_592_000L

///|
/// The session cookie's name.
const SESSION_COOKIE : String = "session"

///|
/// The officer this request's session cookie acts as, or `None` if the
/// request has no session or its token is unknown.
async fn officer_of(store : @store.Store, req : @moonback.Request) -> String? {
  match req.cookie().get(SESSION_COOKIE) {
    Some(token) => store.session(token)
    None => None
  }
}

///|
/// The client a request counts against: Fly's `Fly-Client-IP` if present,
/// else the peer address. Fly's edge sets the header, so only a server
/// reachable without it would let a client name its own key; `mint_all`
/// bounds that case.
fn client_of(req : @moonback.Request) -> String {
  match req.headers.get("Fly-Client-IP") {
    Some(ip) => ip.to_owned()
    None => req.ips().get(0).map(ip => ip.to_owned()).unwrap_or("")
  }
}

///|
/// A new session token: 128 random bits as 32 hex characters.
fn new_token() -> String {
  random_hex(16)
}

///|
/// A new officer's public crew id. It is never the session token, because
/// snapshots and the log publish crew ids.
fn new_officer() -> String {
  "officer-" + random_hex(8)
}

///|
fn random_hex(bytes : Int32) -> String {
  guard @env.rand(bytes) is Some(raw) else {
    abort("session: the platform has no entropy source")
  }
  @crypto.bytes_to_hex_string(raw)
}

///|
/// The `Set-Cookie` value for a new session. `secure` is false only for
/// plain-http development.
fn session_cookie(token : String, secure~ : Bool) -> String {
  let secure = if secure { "; Secure" } else { "" }
  "\{SESSION_COOKIE}=\{token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=\{SESSION_MAX_AGE}\{secure}"
}
