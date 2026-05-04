# syntax=docker/dockerfile:1.7

FROM haskell:9.6.7 AS builder

WORKDIR /src

COPY . .

# Statically link zlib via the bundled C source so the runtime image
# doesn't need libz.so.1. This mirrors the Windows release job's freeze
# patch — the canonical freeze keeps `+pkg-config -bundled-c-zlib` for
# native release builds where the runner has a system zlib.
RUN sed -i 's/zlib -bundled-c-zlib +non-blocking-ffi +pkg-config/zlib +bundled-c-zlib +non-blocking-ffi -pkg-config/' cabal.project.freeze \
 && grep '^             zlib ' cabal.project.freeze

# A two-step "manifests first, sources later" layer split is tempting for
# caching, but Cabal 3.10's `--only-dependencies` still preprocesses the
# in-package library (executable depends on it), which fails before the
# source tree is COPY'd. Just build everything in one RUN.
RUN cabal update \
 && cabal install exe:paninfraspec-gen \
      --installdir=/out \
      --install-method=copy \
      --overwrite-policy=always \
      --enable-executable-stripping

# Use Debian slim (not distroless) for the runtime: the GHC-produced binary
# pulls in libgmp / libffi / libtinfo / libstdc++ via terminfo and base
# runtime, and chasing each missing .so on distroless/cc one tag at a time
# (libz.so.1 → libtinfo.so.6 → ...) was an endless game. apt resolves the
# full closure in one shot.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libgmp10 libffi8 libtinfo6 libstdc++6 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/paninfraspec-gen /usr/local/bin/paninfraspec-gen

WORKDIR /work

ENTRYPOINT ["/usr/local/bin/paninfraspec-gen"]
