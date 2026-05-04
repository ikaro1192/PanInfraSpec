# PanInfraSpec
[![CI](https://github.com/ikaro1192/PanInfraSpec/actions/workflows/ci.yml/badge.svg)](https://github.com/ikaro1192/PanInfraSpec/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ikaro1192/PanInfraSpec)](https://github.com/ikaro1192/PanInfraSpec/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Haskell](https://img.shields.io/badge/language-Haskell-5D4F85)](https://www.haskell.org/)

PanInfraSpec is a Dhall front-end for [Serverspec](https://serverspec.org/).
You describe your nodes and the assertions they should satisfy in
[Dhall](https://dhall-lang.org/), and `paninfraspec-gen` produces the
matching `*_spec.rb`, `spec_helper.rb`, and `Rakefile` for you. PanInfraSpec
**does not run tests** — Serverspec still does that. It just makes the spec
files DRY, type-checked, and easy to regenerate when your inventory changes.

## Install

```sh
brew install ikaro1192/tap/paninfraspec
```

Pre-built tarballs, `.deb` / `.rpm` packages, a Docker image
(`ghcr.io/ikaro1192/paninfraspec-gen`), and a `cabal build` path are
documented in [`docs/install.md`](./docs/install.md).

## Quickstart

```sh
paninfraspec-gen \
  --inventory examples/inventory.dhall \
  --plan      examples/plan.dhall \
  --target    serverspec \
  --out       /tmp/out

cd /tmp/out && bundle exec rake spec   # requires the serverspec gem
```

The generated `out/` directory contains:

```
out/
├── <hostname>_spec.rb   # one per node in the inventory
├── spec_helper.rb       # shared helpers
└── Rakefile             # `rake spec` entry point
```

By default the helpers use Serverspec's `:exec` backend (run locally on the
target). Set `TARGET_HOST=<host>` in the environment to switch to SSH without
editing the generated files.

## How it fits together

```
Dhall preludes  ──►  Generic Semantic AST  ──►  per-backend emitter  ──►  out/<host>_spec.rb
```

The Dhall preludes use smart constructors so unsound combinations (e.g.
`service "nginx" PackageState.Installed`) are rejected at parse time. The
AST and emitter interface are backend-agnostic — Goss, InSpec, and
Testinfra emitters are planned. See
[`docs/architecture.md`](./docs/architecture.md) for the full pipeline.

The three input axes — **inventory**, **plan**, and (optionally) **layout** /
**scaffold** — compose freely:

| Axis | Answers | Docs |
|---|---|---|
| Inventory | which nodes exist? | [`docs/inventory.md`](./docs/inventory.md) |
| Plan | which assertions does each node get? | [`docs/plan.md`](./docs/plan.md) |
| Layout | what filename does each spec land at? | [`docs/layout.md`](./docs/layout.md) |
| Scaffold | what auxiliary files (Rakefile, helpers, …) wrap them? | [`docs/scaffold.md`](./docs/scaffold.md) |

## Documentation

- [Installation](./docs/install.md) — Homebrew, release tarballs, Docker, source
- [Writing an inventory](./docs/inventory.md) — Dhall inventory + Terraform `tfstate` adapter
- [Writing a plan](./docs/plan.md) — selectors, modules, per-host dynamic values
- [Output layout](./docs/layout.md) — `--layout`, PerHost vs PerRole, path validation
- [Scaffolds](./docs/scaffold.md) — `--scaffold`, ansible_spec integration, custom forks
- [CLI reference](./docs/cli.md) — every flag and exit code
- [Resource catalogue](./docs/resources.md) — the 26 Serverspec resources Dhall exposes
- [Architecture](./docs/architecture.md) — the AST and emitter pipeline

See also:

- [`examples/`](./examples) — sample inventory, plan, Terraform state
- [`dhall/`](./dhall) — preludes you import from your own Dhall files
  (`Inventory.dhall`, `Serverspec.dhall`, `Plan.dhall`)
