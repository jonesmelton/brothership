.PHONY: dev build test check

dev:
	warren dev --server-target native

build:
	warren build --server-target native

test:
	moon test --target js
	moon test --target native

check:
	moon run scripts/check.mbtx
