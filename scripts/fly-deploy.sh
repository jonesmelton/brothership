#!/bin/sh
# Deploy HEAD to Fly.io. Untracked files and uncommitted tracked changes never
# ship: this archives the commit and builds that, so the image matches a git
# sha you can read off `fly releases`.
set -eu

cd "$(dirname "$0")/.."

APP=$(sed -n 's/^app = "\(.*\)"$/\1/p' fly.toml)
if [ -z "$APP" ]; then
  echo "fly-deploy: no app name in fly.toml" >&2
  exit 1
fi

tracked=$(git status --porcelain --untracked-files=no)
if [ -n "$tracked" ]; then
  printf 'fly-deploy: tracked files have uncommitted changes:\n%s\n' "$tracked" >&2
  echo "fly-deploy: commit or stash them; deploys ship HEAD only." >&2
  exit 1
fi

untracked=$(git status --porcelain --untracked-files=all | sed -n 's/^?? //p')
if [ -n "$untracked" ]; then
  printf 'fly-deploy: note, untracked files not shipped:\n%s\n' "$untracked" >&2
fi

rev=$(git rev-parse --short HEAD)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git archive HEAD | tar -x -C "$tmp"
fly deploy "$tmp" -a "$APP" --image-label "$rev"
