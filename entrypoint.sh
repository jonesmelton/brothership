#!/bin/sh
set -e

# Rehydrate the volume from object storage if the local database is absent
# (fresh volume, or a destroyed-and-recreated one). -if-replica-exists means a
# first-ever boot with no replica yet is not an error; the server then creates
# the schema.
litestream restore -if-db-not-exists -if-replica-exists -config /etc/litestream.yml "$BROTHERSHIP_DB"

# Run the server as Litestream's child so they share a lifecycle: Litestream is
# PID 1, checkpoints the WAL, and replicates while the server runs.
exec litestream replicate -config /etc/litestream.yml -exec /app/server
