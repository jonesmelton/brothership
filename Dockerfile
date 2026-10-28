# syntax=docker/dockerfile:1

# --- build stage: native linux/amd64 bundle -----------------------------------
FROM debian:12 AS build

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       ca-certificates curl gcc git libc6-dev \
  && rm -rf /var/lib/apt/lists/*

# The installer serves `latest` for linux-x86_64 but returns 403 for the
# toolchain version this repo was written against (0.1.20261020), so the image
# tracks the newest MoonBit release instead of pinning one.
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
ENV PATH=/root/.moon/bin:$PATH
RUN moon version --all \
  && moon install moonbit-community/warren

WORKDIR /app

# Resolve dependencies in a layer keyed only on the manifests, so editing a
# source file does not re-download them. moon fetches the registry index with
# `update` and the packages themselves when it plans a build; the dry run plans
# one without compiling anything.
COPY moon.mod ./
COPY api/moon.pkg api/
COPY cast/moon.pkg cast/
COPY cmd/browser/moon.pkg cmd/browser/
COPY cmd/cast/moon.pkg cmd/cast/
COPY cmd/gate/moon.pkg cmd/gate/
COPY cmd/harness/moon.pkg cmd/harness/
COPY cmd/server/moon.pkg cmd/server/
COPY cmd/speak/moon.pkg cmd/speak/
COPY cmd/survey/moon.pkg cmd/survey/
COPY core/moon.pkg core/
COPY core/math/moon.pkg core/math/
COPY llm/moon.pkg llm/
COPY llm/cache/moon.pkg llm/cache/
COPY llm/gate/moon.pkg llm/gate/
COPY llm/prompt/moon.pkg llm/prompt/
COPY ships/moon.pkg ships/
COPY sim/moon.pkg sim/
COPY speech/moon.pkg speech/
COPY mind/moon.pkg mind/
COPY cmd/audition/moon.pkg cmd/audition/
COPY store/moon.pkg store/
COPY words/moon.pkg words/
RUN moon update \
  && moon build --target native --dry-run > /dev/null

COPY . .
RUN warren build --bundle

# --- litestream binary --------------------------------------------------------
FROM litestream/litestream:0.5 AS litestream

# --- runtime stage ------------------------------------------------------------
FROM debian:12-slim AS runtime

# ca-certificates for the HTTPS PUTs to Tigris.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/dist/server.exe /app/server
COPY --from=litestream /usr/local/bin/litestream /usr/local/bin/litestream
COPY litestream.yml /etc/litestream.yml
COPY entrypoint.sh /app/entrypoint.sh
# The speech prompts, ships' faces and gate policy the server reads at boot.
COPY content /app/content

# Tripwire: a shared library missing from the runtime stage fails the build
# here ("not found" makes ldd exit non-zero) instead of crashing at boot.
RUN ldd /app/server

EXPOSE 8080
ENTRYPOINT ["/app/entrypoint.sh"]
