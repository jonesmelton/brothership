.PHONY: dev build test check sim

dev:
	warren dev --server-target native

build:
	warren build --server-target native

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
