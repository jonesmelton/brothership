# deploy plan: Fly.io with Litestream

Deploy the game server to one Fly.io machine with its sqlite event log on a
volume, replicated by Litestream to a Tigris bucket. A machine that boots
without a database restores it from the bucket, so a destroyed volume, a new
region and a disaster all go through the same path, and the restore drill
rehearses that path.

The setup is ported from `~/code/magic_game` (app `sunwise`), where it has run
since 2026-07 and the destroy-and-restore drill has passed. Its files are the
reference: `litestream.yml`, `entrypoint.sh`, `Dockerfile`, `fly.toml` and
`tools/deploy.rb`. Read them before starting.

Status: shipped 2026-10-27 at https://brothership.fly.dev, one machine in
`ord`. The destroy-and-restore drill passed: with the machine and volume
destroyed, a redeploy restored the seeded log from Tigris and served the same
`seq`. Three steps changed while executing them:

- The MoonBit installer serves only `latest` for `linux-x86_64` (403 for
  `0.1.20261020`), so the image is not pinned to a toolchain version.
- There is no Homebrew formula for Litestream. `scripts/restore-drill.sh`
  takes a binary on `PATH` or in `LITESTREAM` and requires 0.5.
- Later changes make parts of this plan stale: the health check is
  `GET /healthz`, the server makes model calls and reads `MODEL_API_KEY`
  (speakers start only when it is set; `scripts/fly-provision.sh` does not
  set it), and there is no `GET /api/snapshot`: snapshots are per ship at
  `/api/ships/:id/snapshot`, which `scripts/restore-drill.sh` uses.
- A local restore passes the Tigris endpoint as `?endpoint=...&region=auto`
  on the replica URL. The `restore` CLI does not take its endpoint from
  `AWS_ENDPOINT_URL_S3`, so without the query parameter it looks up the
  bucket on AWS proper. The server reads that variable into the config's
  `endpoint:` field, where it does apply.

## facts established before writing this

These were checked on 2026-10-27 against the repo at `0c107aa`.

- `warren build --bundle` produces one file, `dist/server.exe` (2.5 MB on
  macOS), with the browser client and `public/` embedded. On macOS it links
  only `libSystem`. Run from an unrelated directory, it serves `/` (200) and
  `GET /api/snapshot` (200, `{"seq":"0","state":{"clock":"0"}}`). There is no
  `/health` route (404).
- `warren build` refuses a `--dist` outside the project or under `_build`.
  Use the default `dist/`, which is gitignored.
- `cmd/server/main.mbt` reads `WARREN_HOST` (default `127.0.0.1`),
  `WARREN_PORT` (default `4300`) and `BROTHERSHIP_DB` (default
  `brothership.sqlite` in the working directory). It reads no model API key;
  only `cmd/cast` and `cmd/gate` read `MODEL_API_KEY`.
- `Store::open` (`store/store.mbt`) sets `journal_mode = wal`,
  `synchronous = normal` and `foreign_keys = on`. It never checkpoints
  explicitly and sets no `busy_timeout`.
- The repo is git only (no fossil checkout), with no remote.
- The MoonBit installer (`https://cli.moonbitlang.com/install/unix.sh`)
  supports `linux-x86_64` and takes a version as its first argument or in
  `MOONBIT_INSTALL_VERSION`; it downloads
  `https://cli.moonbitlang.com/binaries/<version>/moonbit-linux-x86_64.tar.gz`.
  The local toolchain is `moon 0.1.20261020 (2284bd2)`, `moonc v0.10.16+b1a0e846e`.
  The exact version string the installer expects is not confirmed.
- warren installs with `moon install moonbit-community/warren`.

## decisions this plan makes

| Choice | Value | Reason |
| --- | --- | --- |
| App name | `brothership` | Change if taken. |
| Region | `ord` | Same as sunwise. Ask the user if a demo audience is elsewhere. |
| Machine | `shared-cpu-1x`, 256 MB | The server holds a small snapshot in memory. Move to 512 MB if it OOMs at boot. |
| Volume | 1 GB, named `brothership_data`, mounted at `/data` | Smallest Fly allows. |
| Machines | exactly one, never autostopped | sqlite has one writer and `Store` keeps the snapshot in memory; a second machine would diverge. Autostop would put a cold boot in front of the demo. |
| Litestream | 0.5, `sync-interval: 30s` | The sunwise config. A crash loses at most 30 s of events; the volume survives ordinary restarts and deploys, so only volume loss costs anything. |
| Health check | `GET /api/snapshot` | It reads the in-memory snapshot, so it is cheap and proves the store opened. Add no `/health` route. |
| Deployed source | `git archive HEAD` | The working tree has untracked docs; uncommitted work must not ship. Mirrors `just deploy` in magic_game. |

## steps

Do steps 1 to 6 in a worktree or on a branch, run `make check` before
handing back, and commit at step boundaries. Steps 7 and 9 change live
infrastructure: print the commands for the user to run, the way
`tools/deploy.rb` does, rather than running them.

1. Add `pragma busy_timeout = 5000` to `Store::open`, after the
   `journal_mode` pragma. Litestream holds a read transaction on the database
   and briefly locks it while checkpointing; without a timeout, a write that
   meets that lock fails with `SQLITE_BUSY` at once. `exec` already drains the
   row this pragma returns. The timeout is per connection and cannot be
   observed from outside `Store`, so there is no test for it; say so in the
   commit message.

2. Add `.dockerignore`:

   ```
   .git
   .cache
   .honkmoon
   .mooncakes
   .repos
   _build
   _harness
   dist
   research
   *.sqlite
   *.sqlite-wal
   *.sqlite-shm
   ```

3. Add `litestream.yml`, adapted from sunwise. Keep the singular `replica:`;
   Litestream 0.5 rejects the older `replicas:` list.

   ```yaml
   dbs:
     - path: ${BROTHERSHIP_DB}
       replica:
         url: ${LITESTREAM_REPLICA_URL}
         endpoint: ${AWS_ENDPOINT_URL_S3}
         sync-interval: 30s
   ```

4. Add `entrypoint.sh`, executable:

   ```sh
   #!/bin/sh
   set -e
   litestream restore -if-db-not-exists -if-replica-exists -config /etc/litestream.yml "$BROTHERSHIP_DB"
   exec litestream replicate -config /etc/litestream.yml -exec /app/server
   ```

   `-if-replica-exists` makes the first boot, before any replica exists,
   succeed with an empty volume; `Store::open` then creates the schema.
   `-exec` makes Litestream PID 1 with the server as its child, so they stop
   together.

5. Add `Dockerfile`. Three stages:

   - `build`, `FROM debian:12`: install `curl ca-certificates git gcc
     libc6-dev`; install MoonBit pinned to the local toolchain version
     (`curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s <version>`),
     put `/root/.moon/bin` on `PATH`; `moon install moonbit-community/warren`.
     Copy `moon.mod` and every `moon.pkg` first and run `moon update` and
     `moon install` in their own layer so dependency downloads are cached
     across source edits; then copy the source and run
     `warren build --bundle`.
   - `litestream`, `FROM litestream/litestream:0.5`.
   - `runtime`, `FROM debian:12-slim`: install `ca-certificates` (Litestream
     uploads over HTTPS); copy `dist/server.exe` to `/app/server`, the
     `litestream` binary to `/usr/local/bin/litestream`, `litestream.yml` to
     `/etc/litestream.yml` and `entrypoint.sh` to `/app/entrypoint.sh`; then
     `RUN ldd /app/server` so a missing shared library fails the build instead
     of the boot. `EXPOSE 8080`, `ENTRYPOINT ["/app/entrypoint.sh"]`.

   To find the installer's version string, try in order: the `moon` version
   (`0.1.20261020`), the same with the commit (`0.1.20261020+2284bd2`), then
   `latest`. Check each with `curl -fsI` against the binaries URL above
   before building. If only `latest` resolves, use it and record that the
   image is not pinned.

   Verify locally with `docker build --platform linux/amd64 -t brothership .`
   and run it with a scratch volume and no Litestream env, which exercises
   only the build:
   `docker run --rm -p 8080:8080 -e WARREN_HOST=0.0.0.0 -e WARREN_PORT=8080 -e BROTHERSHIP_DB=/tmp/b.sqlite --entrypoint /app/server brothership`,
   then `curl localhost:8080/api/snapshot`.

6. Add `fly.toml`:

   ```toml
   app = "brothership"
   primary_region = "ord"

   [build]

   [env]
     WARREN_HOST = "0.0.0.0"
     WARREN_PORT = "8080"
     BROTHERSHIP_DB = "/data/brothership.sqlite"

   [[mounts]]
     source = "brothership_data"
     destination = "/data"

   [[vm]]
     size = "shared-cpu-1x"
     memory = "256mb"

   [http_service]
     internal_port = 8080
     force_https = true
     auto_stop_machines = "off"
     auto_start_machines = false
     min_machines_running = 1

     [[http_service.checks]]
       interval = "15s"
       timeout = "2s"
       grace_period = "60s"
       method = "GET"
       path = "/api/snapshot"
   ```

   The 60 s grace period covers the restore at boot.

7. Write `scripts/fly-provision.sh`, a do-nothing script ported from
   magic_game's `tools/deploy.rb`. It prints each live command and waits for
   enter; it runs only read-only checks itself. Drop sunwise's basic-auth and
   session-secret steps; brothership has neither. Its sections:

   1. `fly auth whoami`, then confirm the billed account.
   2. `fly apps create brothership`.
   3. `fly volumes create brothership_data --size 1 --region ord -a brothership --yes`.
   4. `fly storage create --name brothership-data -a brothership --yes`. This
      sets the `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
      `AWS_ENDPOINT_URL_S3` and `BUCKET_NAME` secrets.
   5. `fly secrets set -a brothership LITESTREAM_REPLICA_URL=s3://brothership-data/brothership.sqlite`.
   6. First deploy (step 8), then `curl -fsS https://brothership.fly.dev/api/snapshot`.
   7. The full restore drill (step 9).

8. Write `scripts/fly-deploy.sh`, which ships `HEAD`:

   1. Refuse to run if `git status --porcelain` lists tracked changes; print
      untracked files as a note.
   2. `git archive HEAD` into a temporary directory.
   3. `fly deploy <tmpdir> --image-label $(git rev-parse --short HEAD)`, so
      `fly releases` shows which commit runs.

   `make deploy` runs this script. The provisioning and drill scripts have no
   make targets.

9. Write `scripts/restore-drill.sh` with two modes.

   `local` (no downtime, run after any schema migration):

   1. `fly ssh console -a brothership -C "litestream ltx -config /etc/litestream.yml /data/brothership.sqlite"`
      and fail if it lists no LTX files. Litestream 0.5 replaced the
      `snapshots` command with `ltx`. `fly ssh console -C` runs without a
      shell, so the path is spelled out instead of `$BROTHERSHIP_DB`.
   2. Restore into a temp file with a local `litestream` (`brew install
      litestream`, confirm it is 0.5): `litestream restore -o <tmp>/r.sqlite
      s3://brothership-data/brothership.sqlite`, with the `AWS_*` values
      passed in the environment. `fly secrets list` shows only digests, so
      read them from inside the machine with `fly ssh console -C env` or
      create a separate read-only Tigris key; ask the user which.
   3. `sqlite3 -init /dev/null <tmp>/r.sqlite "pragma integrity_check"`
      must print `ok`.
   4. Compare `select max(seq) from event` in the restore against the live
      `seq` from `GET /api/snapshot`. The restore may trail by up to 30 s of
      events; anything more is a failure.

   `full` (destroys the volume, about a minute or two of downtime, run once
   before submission on 2026-11-04 and after infrastructure changes). Print
   these for the user, as in step 7:

   1. Play until the log has events, wait at least 30 s, and run local step 1.
   2. Record `seq` from `/api/snapshot`.
   3. `fly machines list` and `fly volumes list`; note the ids.
   4. `fly machine destroy <id> --force`, then `fly volumes destroy <id> --yes`
      (a volume can't be destroyed while attached).
   5. `fly volumes create brothership_data --size 1 --region ord --yes`.
   6. `scripts/fly-deploy.sh`.
   7. `seq` from `/api/snapshot` must equal the recorded value.

## risks

- **Linux build of the native stack.** Everything above step 5 is verified
  on macOS only. moonbitlang/async, the vendored sqlite C and moonback have
  not been built for linux in this repo. If the build fails, diagnose it and
  patch or vendor the package (see `AGENTS.md` on MoonBit); don't switch the
  server to wasm.
- **The image may need more than glibc.** `ldd` in step 5 catches this at
  build time; add the missing package to the runtime stage.
- **Lost tail on volume loss.** Up to 30 s of events can be missing after a
  restore. Clients adopt the server snapshot on their next receipt or
  reload, so they recover, but a player's last actions disappear.
- **`seq` reuse after a lossy restore.** `event.seq` is an `integer primary
  key` without `autoincrement` (`store/schema.mbt`), so sequence numbers lost
  in the tail are reused by new events. A client that saw a lost `seq` adopts
  the server snapshot anyway; this matters only if something outside the
  server starts storing `seq`.
- **Litestream 0.5 interface.** Command names and flags here are the ones
  sunwise uses, not checked against current Litestream docs. If a command is
  rejected, check `litestream <cmd> -h` in the image before changing the
  approach.

## out of scope

- Model API keys. The server makes no model calls yet; when it does, add
  `MODEL_API_KEY` with `fly secrets set` and leave `llm/cache` off in
  production.
- Snapshot retention, plain-file backups and point-in-time restore. sunwise
  lists these as release hardening; a hackathon build doesn't need them.
- Access control. The deployed game is public. Ask the user whether the demo
  needs a gate.
- A custom domain.
