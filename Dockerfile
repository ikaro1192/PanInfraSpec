# syntax=docker/dockerfile:1.7

FROM haskell:9.6.7 AS builder

WORKDIR /src

COPY . .

# Switch the Haskell `zlib` binding to its bundled C source so the resulting
# executable has no runtime dependency on libz.so.1 — that library is absent
# from gcr.io/distroless/cc-debian12 where the binary is shipped, and was
# causing `paninfraspec-gen --help` to fail with "cannot open shared object
# file: libz.so.1". This mirrors the Windows release job's freeze patch.
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

FROM gcr.io/distroless/cc-debian12

COPY --from=builder /out/paninfraspec-gen /usr/local/bin/paninfraspec-gen

WORKDIR /work

ENTRYPOINT ["/usr/local/bin/paninfraspec-gen"]
