///| Adapter: any `(Request) -> Response raise` closure as a Transport.
struct FnTransport {
  f : (@core.Request) -> @core.Response raise @core.CassetteError
}

///|
impl @recorder.Transport for FnTransport with send(self, req) {
  (self.f)(req)
}

///| Async path: Transport is sync, so wrap an async call by hand.
async fn cached_call(
  s : @recorder.Session,
  req : @core.Request,
  live : async (@core.Request) -> @core.Response,
) -> @core.Response {
  match s.try_replay(req) {
    Some(r) => r
    None => s.record(req, live(req))
  }
}
