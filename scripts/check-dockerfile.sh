#!/bin/sh
# Fails if a tracked package manifest is missing from the Dockerfile's
# dependency layer, which copies each moon.pkg by hand (COPY flattens globs).
set -eu
cd "$(dirname "$0")/.."

status=0
for f in $(git ls-files '*moon.pkg'); do
  if ! grep -qxF "COPY $f $(dirname "$f")/" Dockerfile; then
    echo "Dockerfile: missing 'COPY $f $(dirname "$f")/'" >&2
    status=1
  fi
done
exit $status
