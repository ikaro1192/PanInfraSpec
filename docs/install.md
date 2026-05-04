# Installation

PanInfraSpec ships a single executable, `paninfraspec-gen`. Pick whichever
delivery channel suits your environment — they all produce the same binary.

## Homebrew (macOS)

```sh
brew install ikaro1192/tap/paninfraspec
```

The formula lives in [ikaro1192/homebrew-tap](https://github.com/ikaro1192/homebrew-tap)
and builds `paninfraspec-gen` from source, so the first install takes a few
minutes. Works on both Apple Silicon and Intel Macs.

## From a release asset

Pre-built binaries are published on every tag at
[GitHub Releases](https://github.com/ikaro1192/PanInfraSpec/releases/latest).

| Platform | Asset |
|---|---|
| Linux x86_64 | `paninfraspec-<version>-linux-x86_64.tar.gz` (also `.deb` / `.rpm`) |
| Linux aarch64 | `paninfraspec-<version>-linux-aarch64.tar.gz` (also `.deb` / `.rpm`) |
| macOS arm64 | `paninfraspec-<version>-darwin-arm64.tar.gz` |
| Windows x86_64 | `paninfraspec-<version>-windows-x86_64.zip` |

Tarball install (Linux / macOS):

```sh
VERSION=0.4.0          # pick the tag you want
ARCH=linux-x86_64      # or linux-aarch64, darwin-arm64
curl -L "https://github.com/ikaro1192/PanInfraSpec/releases/download/v${VERSION}/paninfraspec-${VERSION}-${ARCH}.tar.gz" \
  | tar -xz
sudo mv "paninfraspec-${VERSION}-${ARCH}/bin/paninfraspec-gen" /usr/local/bin/
```

The Linux tarballs are dynamically linked against glibc, so they work on
Ubuntu / Debian / RHEL / Fedora and most other glibc-based distros. Alpine
and other musl-based distros are not yet covered by the prebuilt assets;
build from source there until a musl-static asset is added.

On Debian/Ubuntu and RHEL/Fedora the `.deb` / `.rpm` from the same release
are an alternative if you want package-manager integration (uninstall,
upgrade tracking).

## Docker (recommended for CI / one-shot use)

```sh
docker run --rm -v "$PWD":/work \
  ghcr.io/ikaro1192/paninfraspec-gen:0.4 \
  --inventory examples/inventory.dhall \
  --plan      examples/plan.dhall \
  --target    serverspec \
  --out       /work/out
```

Each release publishes `latest`, the full version (`0.5.0.0`), and pin-friendly
`major.minor` / `major.minor.patch` tags to
[ghcr.io/ikaro1192/paninfraspec-gen](https://github.com/ikaro1192/PanInfraSpec/pkgs/container/paninfraspec-gen).
Built for `linux/amd64` and `linux/arm64`. The image only generates spec
files; running `rake spec` afterwards is still the user's responsibility.

## From source

```sh
cabal build
```

This produces the `paninfraspec-gen` executable. After it is built you only
ever interact with Dhall files and the CLI — no Haskell knowledge required.
