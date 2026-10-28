.PHONY: dev build deploy test check sim

# The dev log lives in _build: warren's watcher ignores that directory, but a
# sqlite file in the project root makes every committed event rebuild and
# reload the client.
BROTHERSHIP_DB ?= _build/brothership.sqlite

dev:
	@mkdir -p _build
	ulimit -n 4096; BROTHERSHIP_DB=$(BROTHERSHIP_DB) warren dev --server-target native

build:
	warren build --server-target native

# Ships HEAD to Fly.io; refuses tracked changes. See scripts/fly-deploy.sh.
deploy:
	scripts/fly-deploy.sh

test:
	moon test --target js
	moon test --target native

check:
	moon run scripts/check.mbtx

# The crossing simulator, served on its own at http://127.0.0.1:4311.
# The raised file-descriptor limit is for warren's watcher, which hits
# "Too many open files" at the default 256.
sim:
	ulimit -n 4096; warren dev --direct --browser-entry cmd/harness --port 4311
