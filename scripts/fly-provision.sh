#!/bin/sh
# First-time provisioning of brothership on Fly.io, from magic_game's
# tools/deploy.rb. It changes no live state itself: it prints each state-changing
# command, waits for you to press enter, and runs only read-only checks.
#
# Safe to re-run: skip the steps whose resources already exist.
#
#   APP     Fly app name        (default: brothership)
#   REGION  Fly primary region  (default: ord)
#   VOLUME  volume name         (default: brothership_data)
#   BUCKET  Tigris bucket       (default: brothership-data)
set -eu

APP=${APP:-brothership}
REGION=${REGION:-ord}
VOLUME=${VOLUME:-brothership_data}
BUCKET=${BUCKET:-brothership-data}
URL="https://${APP}.fly.dev/api/snapshot"

wait() {
  printf '\n  press enter when done (ctrl-c to stop) '
  read -r _
}

section() {
  printf '\n%s\n%s\n%s\n' "------------------------------------------------------------------------" "$1" "------------------------------------------------------------------------"
}

# Print an instruction and block.
manual() {
  printf '\n== %s ==\n' "$1"
  shift
  for line in "$@"; do printf '  %s\n' "$line"; done
  wait
}

# Print a command to paste and run yourself, then block.
paste() {
  printf '\n== %s ==\n' "$1"
  shift
  cmd=$1
  shift
  for line in "$@"; do printf '  %s\n' "$line"; done
  printf '\n  %s\n' "$cmd"
  wait
}

# Run a read-only command.
run() {
  printf '\n== %s ==\n' "$1"
  shift
  cmd=$1
  shift
  for line in "$@"; do printf '  %s\n' "$line"; done
  printf '  $ %s\n' "$cmd"
  sh -c "$cmd" || true
}

section "brothership -> Fly.io + Litestream provisioning"
printf '\n  app:    %s\n  region: %s\n  volume: %s\n  bucket: %s\n' "$APP" "$REGION" "$VOLUME" "$BUCKET"
printf '\n  This prints live commands for you to run; it changes no state itself.\n'

# --- 1. account ---------------------------------------------------------------
section "1. Account"
run "flyctl is authenticated" "fly auth whoami"
manual "Confirm the account above is the one you intend to bill." \
  "If not, run \`fly auth login\` and re-run this script."

# --- 2. app -------------------------------------------------------------------
section "2. App"
run "Does the app already exist?" "fly apps list | grep -w ${APP} || echo '(not found -- create it below)'"
paste "Create the app (skip if it already exists)" \
  "fly apps create ${APP}" \
  "fly.toml already pins app = \"${APP}\" and primary_region = \"${REGION}\"."

# --- 3. volume ----------------------------------------------------------------
section "3. Volume"
run "Existing volumes for this app?" "fly volumes list -a ${APP} 2>/dev/null || echo '(none / app not ready)'"
paste "Create the sqlite volume (skip if one named ${VOLUME} exists)" \
  "fly volumes create ${VOLUME} --size 1 --region ${REGION} -a ${APP} --yes" \
  "One volume in one region. Durability comes from Litestream, not the volume," \
  "because sqlite has one writer and the server keeps its snapshot in memory."

# --- 4. object storage (Tigris) ------------------------------------------------
section "4. Object storage (Tigris)"
paste "Provision the Tigris bucket" \
  "fly storage create --name ${BUCKET} -a ${APP} --yes" \
  "This sets the app's secrets automatically: AWS_ACCESS_KEY_ID," \
  "AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT_URL_S3 and BUCKET_NAME." \
  "If the bucket already exists, skip this, but confirm the secrets are" \
  "present with: fly secrets list -a ${APP}"

# --- 5. secrets ----------------------------------------------------------------
section "5. Secrets"
run "Secrets currently set" "fly secrets list -a ${APP} 2>/dev/null || echo '(app not ready)'"
paste "Point Litestream at the bucket" \
  "fly secrets set -a ${APP} LITESTREAM_REPLICA_URL=s3://${BUCKET}/brothership.sqlite" \
  "litestream.yml also reads AWS_ENDPOINT_URL_S3, which step 4 set."

# --- 6. first deploy -----------------------------------------------------------
section "6. First deploy (empty volume)"
manual "Ship HEAD, not the working tree." \
  "scripts/fly-deploy.sh refuses tracked changes and deploys git archive HEAD," \
  "so commit first and check what git log shows."
paste "Build on Fly's remote builder and deploy" \
  "scripts/fly-deploy.sh" \
  "The first build is slow: it downloads the MoonBit toolchain and every" \
  "mooncakes dependency. Later builds reuse that layer."
run "Health check (allow the 60 s grace period after deploy)" \
  "curl -fsS -o /dev/null -w 'snapshot: %{http_code}\\n' ${URL}" \
  "Expect 200. The check reads the in-memory snapshot, so it also proves the" \
  "store opened on the mounted volume."

# --- 7. restore drill ----------------------------------------------------------
section "7. Restore drill"
manual "Rehearse the restore path before trusting it." \
  "scripts/restore-drill.sh local proves the replica is readable and current" \
  "without downtime. Run it once the game has events and at least one sync" \
  "interval (30 s) has passed."
manual "Then run the full drill, which destroys the volume." \
  "scripts/restore-drill.sh full prints the destroy-and-restore commands." \
  "Run it once before submission and after any infrastructure change."

section "Done"
printf '\n  Routine deploys from here: scripts/fly-deploy.sh\n\n'
