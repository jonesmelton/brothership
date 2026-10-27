///|
fn req(prompt : String) -> @core.Request {
  @core.Request::new("anthropic", "claude-sonnet-5-5", {
    "messages": [{ "role": "user", "content": prompt }],
    "temperature": 0,
  })
}

///|
test "record via closure transport, replay out of order offline" {
  let calls = Ref(0)
  let t = FnTransport::{
    f: fn(r) {
      calls.val += 1
      let p = r.body.stringify()
      @core.Response::ok({ "text": "echo:" + p.length().to_string() }, usage=@core.Usage::new(10, 3))
    },
  }
  let s = @mooncassette.auto_session(@core.Cassette::new("demo"), t)
  let a = s.send(req("ship A"))
  let b = s.send(req("ship B"))
  let a2 = s.send(req("ship A")) // hit, no call
  assert_eq(calls.val, 2)
  assert_true(a == a2)
  let text = @mooncassette.save(s)
  // playback: no transport possible; replay B before A
  let p = @mooncassette.replay_session(text)
  assert_true(p.send(req("ship B")) == b)
  assert_true(p.send(req("ship A")) == a)
  let miss : Result[@core.Response, Error] = try Ok(p.send(req("ship C"))) catch { e => Err(e) }
  guard miss is Err(@core.CassetteError::NoMatch(_)) else { fail("expected NoMatch") }
}

///|
async test "async live call via try_replay + record" {
  let s = @recorder.Session::new(@core.Cassette::new("async"), mode=Auto)
  let n = Ref(0)
  let live = async fn(_r : @core.Request) -> @core.Response {
    n.val += 1
    @async.sleep(5)
    @core.Response::ok({ "text": "hi" })
  }
  let r1 = cached_call(s, req("x"), live)
  let r2 = cached_call(s, req("x"), live)
  assert_eq(n.val, 1)
  assert_true(r1 == r2)
}

///|
test "api-key in body is sanitized in saved cassette?" {
  let t = FnTransport::{ f: fn(_) { @core.Response::ok({ "ok": true }) } }
  let s = @mooncassette.record_session(@core.Cassette::new("k"), t)
  let r = @core.Request::new("openai", "m", { "api_key": "sk-secret123", "messages": [] })
  ignore(s.send(r))
  let text = @mooncassette.save(s)
  assert_false(text.contains("sk-secret123"))
}
