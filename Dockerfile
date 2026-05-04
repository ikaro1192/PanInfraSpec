# syntax=docker/dockerfile:1.7

FROM haskell:9.6.7 AS builder

WORKDIR /src

COPY cabal.project cabal.project.freeze paninfraspec.cabal ./

RUN cabal update \
 && cabal build --only-dependencies exe:paninfraspec-gen

COPY . .

RUN cabal install exe:paninfraspec-gen \
      --installdir=/out \
      --install-method=copy \
      --overwrite-policy=always \
      --enable-executable-stripping

FROM gcr.io/distroless/cc-debian12

COPY --from=builder /out/paninfraspec-gen /usr/local/bin/paninfraspec-gen

WORKDIR /work

ENTRYPOINT ["/usr/local/bin/paninfraspec-gen"]
