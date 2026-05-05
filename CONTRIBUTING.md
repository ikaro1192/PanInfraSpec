# Contributing to PanInfraSpec

Contributions are welcome — bug reports, feature ideas, and pull requests alike. Feel free to open an issue anytime. Please note that responses may not be immediate, as this project is maintained on a best-effort basis.

## Reporting Bugs

Found something wrong? Before opening an issue, please search [existing issues](https://github.com/ikaro1192/PanInfraSpec/issues) to avoid duplicates. If nothing matches, please open a new one. It helps to include:

- PanInfraSpec version (`paninfraspec-gen --version`)
- Selected backend (`--target serverspec`, etc.) and host OS
- The Dhall input that triggered the issue (inventory / plan / layout / scaffold), or a minimal reproducer
- The full command line you ran and its output (stderr, generated files if relevant)
- Steps to reproduce

## Feature Requests

Have an idea? Before opening an issue, please search [existing issues](https://github.com/ikaro1192/PanInfraSpec/issues) to see if it has already been discussed. If not, please open a new one and describe:

- The problem or use case you're trying to solve
- Your proposed solution or behavior
- Which axis it touches — inventory, plan, layout, scaffold, IR, or a specific backend emitter
- How it fits with the [Design Principles](#design-principles) of PanInfraSpec

PanInfraSpec is designed to grow along specific axes — new backend emitters, new Dhall preludes, new source-of-truth adapters, additional resources in existing preludes — and contributions in those directions are very welcome. What it tries *not* to grow into is a test runner, a config-management runtime, or a durable inventory store; proposals heading that way, or ones that would require backend-specific concepts to leak into the IR, may not be accepted. Discussing the idea upfront in an issue is always a good start.

## Prerequisites

| Tool | Version |
|------|---------|
| GHC | 9.6+ |
| Cabal | 3.10+ |
| Nix (flakes) | optional, for `nix build` / `nix run` |

Install GHC and Cabal via [GHCup](https://www.haskell.org/ghcup/), or use the pinned toolchain from `flake.nix` (`nix develop`).

## Build & Test

```bash
# Build everything (library + paninfraspec-gen)
cabal build all

# Unit / property / golden tests (tasty + HUnit + QuickCheck + tasty-golden)
cabal test all --test-show-details=direct

# Run a single test module (any tasty pattern works)
cabal test paninfraspec-test --test-options='-p "Unit.Layout"'

# Try the generator end-to-end against the bundled examples
cabal run paninfraspec-gen -- \
  --inventory examples/inventory.dhall \
  --plan      examples/plan.dhall \
  --target    serverspec \
  --out       /tmp/out

# Optional: build via Nix (matches the CI nix-build job)
nix build .#paninfraspec
```

Golden fixtures live under `test/Golden/` and are LF-only; if you regenerate them on Windows, make sure your editor / git config does not rewrite line endings (CI sets `core.autocrlf=false` for this reason).

CI runs `cabal build` + `cabal test` on Ubuntu, macOS, and Windows for every push to `main` and every pull request, plus `nix build` on Linux.

## Code Conventions

### Haskell style

- All `-Wall` / `-Werror` warnings must be resolved. Do not silence them with `{-# OPTIONS_GHC -Wno-... #-}` unless genuinely necessary — the cabal file enables `-Werror` and several extra warnings (`-Wincomplete-uni-patterns`, `-Wpartial-fields`, `-Werror=incomplete-patterns`).
- Keep functions small and pure. The library is essentially a pure pipeline (Dhall → IR → emitter); IO belongs at the CLI edge in `PanInfraSpec.CLI` and `app/Main.hs`.
- Prefer total functions over partial ones; pattern matches must be exhaustive.
- Default extensions are set in `paninfraspec.cabal` (`OverloadedStrings`, `LambdaCase`, `RecordWildCards`, `StrictData`, …) — use them rather than re-enabling per file.

### Module structure

```
PanInfraSpec.IR              -- Backend-agnostic semantic IR (re-exports the submodules)
PanInfraSpec.IR.Inventory    -- Hosts, roles, attributes
PanInfraSpec.IR.Selector     -- Plan selectors (which hosts get which assertions)
PanInfraSpec.IR.Assertion    -- Resource / property / matcher tree
PanInfraSpec.Dhall           -- Dhall decoding into the IR
PanInfraSpec.Resolve         -- Inventory × Plan → per-host assertion sets, conflict detection
PanInfraSpec.Layout          -- --layout handling (PerHost, PerRole, path validation)
PanInfraSpec.Scaffold        -- --scaffold handling (Rakefile, helpers, static files)
PanInfraSpec.Emit            -- Backend dispatcher (routes on --target)
PanInfraSpec.Emit.Serverspec -- Reference Serverspec emitter
PanInfraSpec.SoT             -- Source-of-truth adapters (Terraform tfstate, …)
PanInfraSpec.SoT.Terraform
PanInfraSpec.DumpPlan        -- --dump-plan diagnostic output
PanInfraSpec.CLI             -- optparse-applicative wiring
```

New functionality belongs in the most specific existing namespace. **The IR and dispatcher are intentionally backend-agnostic** — backend-specific concepts (Rakefile, `bundle exec rake spec`, `*_spec.rb`) must stay inside `PanInfraSpec.Emit.Serverspec` (or a new `PanInfraSpec.Emit.<Backend>` module) and the corresponding Dhall prelude, never in `PanInfraSpec.IR.*`, `PanInfraSpec.Resolve`, or `PanInfraSpec.Scaffold`.

### Adding a new backend

The whole point of the IR is that this is small and additive:

1. Add a Dhall prelude under `dhall/` (e.g. `dhall/Inspec.dhall`) using smart constructors so unsound combinations are rejected at parse time.
2. Add an emitter module `PanInfraSpec.Emit.<Backend>` that consumes the IR and produces files.
3. Wire the new `--target` value into the dispatcher in `src/PanInfraSpec/Emit.hs`.
4. Add a golden test under `test/Golden/<backend>/` and an emit property test if the output has structural invariants worth checking.

Existing inputs, the IR, and other emitters must not change. If you find yourself needing to modify the IR to fit a new backend, that's a signal to discuss the design in an issue first — the IR is meant to be a stable contract.

## Commit Messages

- **English only** — subject line, body, and any trailers
- Use the imperative mood: `Add InSpec emitter`, not `Added` or `Adds`
- Reference a GitHub issue when relevant: `Fixes #123`

## Pull Requests

Before submitting a PR, please search [existing issues and PRs](https://github.com/ikaro1192/PanInfraSpec/issues) to check whether the same change is already in progress. For non-trivial changes, opening an issue to discuss the approach first helps avoid wasted work — especially for changes that touch the IR, the dispatcher, or add a new backend. Obvious typo fixes and small documentation corrections can skip that step.

- One logical change per PR
- Ensure local tests pass (`cabal test all`)
- If your change affects the IR, resolution, or an emitter, add or update the relevant test under `test/Unit/`, `test/Property/`, `test/Roundtrip/`, or `test/Golden/`
- If you intentionally regenerate a golden fixture, eyeball the diff and explain the change in the PR body
- Update `docs/` if your change affects CLI flags, Dhall preludes, output layout, or other observable behavior
- Update `README.md` if your change affects the quickstart or the documented input axes
- Include `Fixes #<issue>` in the PR body to link the issue

## Design Principles

To keep PanInfraSpec simple and reliable, contributions should align with its core philosophy:

- **Backend-agnostic IR** — the semantic IR is the contract between input and output. New backends plug in as a Dhall prelude + emitter; they must not require IR changes.
- **Reject unsound input early** — Dhall smart constructors disallow nonsensical combinations (e.g. `service "nginx" PackageState.Installed`) at parse time; the resolver fails fast on conflicting assertions rather than emitting spec files that are guaranteed to fail at run time.
- **Generator only, not a runner** — PanInfraSpec emits spec files; the backend's own runner (`rake spec`, `inspec exec`, …) executes them. We do not embed test execution.
- **Deterministic, regeneratable output** — given the same inputs, generation produces byte-identical output. Golden tests guard this.
- **Pure Haskell, statically linkable** — preserve the no-C-deps property so `nix build` and the release tarballs stay self-contained across Linux / macOS / Windows.
- **Do one thing well** — input axes (inventory / plan / layout / scaffold) compose freely, but the tool stays a generator. It is not an inventory database, not a config-management runtime, and not a test runner.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
