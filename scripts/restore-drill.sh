#!/bin/sh
# Rehearse Litestream's restore path for the deployed game.
#
#   scripts/restore-drill.sh local   restore the replica into a temp file and
#                                    check it against the live server; no downtime
#   scripts/restore-drill.sh full    print the volume-destroying drill (this one
#                                    changes live state, so you run it yourself)
#
# Run `local` after any schema migration; run `full` before submission and after
# infrastructure changes.
set -eu

APP=${APP:-brothership}
BUCKET=${BUCKET:-brothership-data}
ENDPOINT=${ENDPOINT:-fly.storage.tigris.dev}
LITESTREAM=${LITESTREAM:-litestream}
DB=/data/brothership.sqlite
REPLICA="s3://${BUCKET}/brothership.sqlite?endpoint=${ENDPOINT}&region=auto"
SNAPSHOT="https://${APP}.fly.dev/api/snapshot"

wait() {
  printf '\n  press enter when done (ctrl-c to stop) '
  read -r _
}

paste() {
  printf '\n== %s ==\n' "$1"
  shift
  cmd=$1
  shift
  for line in "$@"; do printf '  %s\n' "$line"; done
  printf '\n  %s\n' "$cmd"
  wait
}

local_drill() {
  # There is no Homebrew formula; the release tarball is the install path.
  if ! command -v "$LITESTREAM" > /dev/null 2>&1; then
    echo "restore-drill: $LITESTREAM is not on PATH. Download the 0.5 release" >&2
    echo "binary for this OS from https://github.com/benbjohnson/litestream/releases" >&2
    echo "and put it on PATH, or set LITESTREAM to its path." >&2
    exit 1
  fi
  version=$("$LITESTREAM" version)
  case "$version" in
    0.5.*) ;;
    *)
      echo "restore-drill: litestream 0.5 is required, found $version" >&2
      exit 1
      ;;
  esac

  # litestream 0.5 replaced `snapshots` with `ltx`; the listing is also the
  # proof that something has replicated at all.
  echo "== replica files =="
  listing=$(fly ssh console -a "$APP" -C "litestream ltx -config /etc/litestream.yml $DB")
  echo "$listing"
  if ! printf '%s\n' "$listing" | grep -qE '^[0-9]+[[:space:]]+[0-9a-f]{16}'; then
    echo "restore-drill: no LTX files in the replica; not trusting it. Check" >&2
    echo "LITESTREAM_REPLICA_URL and the AWS_* secrets before rerunning." >&2
    exit 1
  fi

  # Credentials live in the app's secrets. `fly secrets list` shows digests, so
  # read the values from inside the machine; they are exported, never echoed.
  if [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
    creds=$(fly ssh console -a "$APP" -C env)
    AWS_ACCESS_KEY_ID=$(printf '%s\n' "$creds" | sed -n 's/^AWS_ACCESS_KEY_ID=//p')
    AWS_SECRET_ACCESS_KEY=$(printf '%s\n' "$creds" | sed -n 's/^AWS_SECRET_ACCESS_KEY=//p')
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  fi
  AWS_REGION=auto
  export AWS_REGION

  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' EXIT

  echo "== restore =="
  "$LITESTREAM" restore -o "$dir/restored.sqlite" "$REPLICA"

  echo "== integrity =="
  sqlite3 -init /dev/null "$dir/restored.sqlite" "pragma integrity_check" | sed 's/^/  /'

  restored=$(sqlite3 -init /dev/null "$dir/restored.sqlite" "select coalesce(max(seq), 0) from event")
  live=$(curl -fsS "$SNAPSHOT" | sed -n 's/.*"seq":"\([0-9]*\)".*/\1/p')
  echo "== seq =="
  echo "  restored: $restored"
  echo "  live:     $live"

  if [ -z "$live" ]; then
    echo "restore-drill: no seq in $SNAPSHOT" >&2
    exit 1
  fi
  if [ "$restored" -gt "$live" ]; then
    echo "restore-drill: replica is ahead of the live server; wrong app?" >&2
    exit 1
  fi
  if [ "$restored" -eq 0 ] && [ "$live" -ne 0 ]; then
    echo "restore-drill: replica has no events while the server has $live." >&2
    exit 1
  fi

  # The restore may trail by up to one sync interval (30 s) of events. The LTX
  # listing above should show a file from the last couple of minutes; older
  # means replication has stopped and the seq gap is not explainable by lag.
  echo "  (a gap is fine only if the newest LTX file above is recent)"
}

full_drill() {
  echo "This destroys the data volume to prove the boot-time restore. Allow a"
  echo "minute or two of downtime, and run it once the local drill passes."
  wait

  paste "Seed events, wait 30 s, then run the local drill" \
    "scripts/restore-drill.sh local"

  paste "Record the live seq" \
    "curl -fsS ${SNAPSHOT} | sed -n 's/.*\"seq\":\"\\([0-9]*\\)\".*/\\1/p'"

  paste "Note the ids you are about to destroy" \
    "fly machines list -a ${APP}; fly volumes list -a ${APP}"

  paste "Destroy the machine first (a volume cannot be destroyed while attached)" \
    "fly machine destroy <MACHINE_ID> -a ${APP} --force"

  paste "Destroy the volume (this deletes the local data)" \
    "fly volumes destroy <VOLUME_ID> -a ${APP} --yes" \
    "Replace <VOLUME_ID> with the id from the list above."

  paste "Recreate the volume" \
    "fly volumes create brothership_data --size 1 --region ord -a ${APP} --yes"

  paste "Redeploy so a machine boots against the fresh volume" \
    "scripts/fly-deploy.sh" \
    "entrypoint.sh restores from Tigris when the database is absent."

  paste "Confirm the seq you recorded is back" \
    "curl -fsS ${SNAPSHOT}" \
    "A lost tail of up to 30 s of events is expected; anything more is a failure."
}

case "${1:-}" in
  local) local_drill ;;
  full) full_drill ;;
  *)
    echo "usage: $0 local|full" >&2
    exit 2
    ;;
esac
