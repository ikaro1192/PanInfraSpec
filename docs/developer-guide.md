# Developer Guide

A bird's-eye internal map of the codebase for people who want to *change*
PanInfraSpec — not just use it. The goal is to make it obvious **what lives
where** and **which other parts a change ripples into**.

The high-level pipeline diagram and policy are in
[`docs/architecture.md`](./architecture.md); contribution workflow, coding
conventions, and the new-backend procedure are in
[`CONTRIBUTING.md`](../CONTRIBUTING.md). This guide fills the gap between
those two and serves as the internal navigation aid.

---

## 1. What PanInfraSpec is (and isn't)

PanInfraSpec is a **pure compiler** from input descriptions (Dhall, Terraform
state, …) to **per-backend spec files**.

| In scope | Out of scope |
|---|---|
| Parse Dhall preludes into the IR | Run the generated specs (Serverspec/InSpec own that) |
| Emit spec files for multiple backends | Configuration management (Ansible/Chef/Puppet territory) |
| Resolve `Inventory × Plan` into per-host jobs | Persistent inventory storage / host management |
| Decide output paths (Layout) and auxiliary files (Scaffold) | Replicating backend-runtime features |

`CONTRIBUTING.md` (Feature Requests) explicitly rejects changes that leak
backend-specific vocabulary into the IR.

---

## 2. Directory layout

```
.
├── app/Main.hs                       -- CLI entry point (thin optparse-applicative wrapper)
├── src/PanInfraSpec/
│   ├── CLI.hs                        -- Flags + run :: Options -> IO ExitCode
│   ├── Dhall.hs                      -- Dhall input loaders + layer-2 validate
│   ├── IR.hs                         -- Re-export façade for the IR
│   ├── IR/Inventory.hs               -- Node / Role / CustomAttribute
│   ├── IR/Selector.hs                -- Selector (And/Or/Not are Haskell-only)
│   ├── IR/Expr.hs                    -- Typed expression sub-IR (issue #57): narrow alternative to ALRubyExpr
│   ├── IR/Assertion.hs               -- Assertion / Mapping / PlanFile / Job / ExecutionPlan
│   ├── Resolve.hs                    -- Inventory × Plan → ExecutionPlan
│   ├── Layout.hs                     -- Layout (output paths) + path validation
│   ├── Scaffold.hs                   -- Scaffold (auxiliary files: Rakefile, hosts, …)
│   ├── Scaffold/Defaults/Serverspec.hs -- Built-in default scaffold
│   ├── Emit.hs                       -- Backend registry + emitFor dispatcher
│   ├── Emit/Backend.hs               -- BackendEntry type (emitter + allowedKinds)
│   ├── Emit/Serverspec.hs            -- Reference Serverspec emitter + schema
│   ├── DumpPlan.hs                   -- --dump-plan rendering
│   ├── SoT.hs                        -- Source-of-Truth typeclass
│   └── SoT/Terraform.hs              -- tfstate v4 → [Node] adapter
├── dhall/                            -- Preludes users import from their own Dhall
│   ├── Inventory.dhall
│   ├── Plan.dhall
│   ├── Layout.dhall
│   ├── Serverspec.dhall              -- Smart-constructor surface for Serverspec
│   ├── Scaffold.dhall
│   └── Scaffold/{Serverspec,AnsibleSpec}.dhall
├── examples/                         -- End-to-end samples used by docs
├── docs/                             -- User-facing documentation (this file too)
└── test/                             -- tasty test suite (see §7)
```

The `exposed-modules` list in `paninfraspec.cabal` is the source of truth
for the library surface. Add any new module there too — `-Werror` will fail
the build if a module is left out.

---

## 3. End-to-end pipeline

`PanInfraSpec.CLI.run` orchestrates the whole pipeline. The middle of the
pipeline is a chain of pure functions; only the edges (loading files,
writing output) do IO.

```
                      ┌─ FromDhall ──────► loadInventory ──┐
   --inventory /  ────┤                                    ├─► [Node]
   --from-terraform   └─ FromTerraformState ─► toNodes ────┘
                                                           │
                                  buildFilterSelector / filterNodes
                                                           ▼
   --plan ──► loadPlan ──► PlanFile { targetBackend, mappings }
                                          │
              checkTargetMatches  (does --target == pf.targetBackend?)
                                          ▼
                resolve target nodes mappings ──► ExecutionPlan
                                          ▼
                              validate :: ExecutionPlan
                       ├── reject empty / unknown backend
                       └── reject empty kind / kind outside backend allowlist
                                          ▼
                          --dump-plan ? ── yes ─► dumpPlan → stdout
                                          │ no
                                          ▼
                resolveLayout / resolveScaffold (defaults if absent)
                                          ▼
                       emitFor scaffold layout ep
                       ── Map.lookup target registry
                       └─► beEmitter ──► Map FilePath Text
                                          ▼
                                 writeAll outDir files
```

Mind the difference between `PlanFile` and `ExecutionPlan`:

- **`PlanFile`** is the raw user input from Dhall (`targetBackend` + a list
  of `Mapping`s).
- **`ExecutionPlan`** is the *resolved* form after running selectors against
  the inventory. **Emitters only see `ExecutionPlan`** — they never inspect
  raw selectors or the original `PlanFile`.

---

## 4. Validation lives in four layers

Different validations live in different places on purpose; remembering the
split keeps you from editing the wrong file.

| Layer | Where | What it checks |
|---|---|---|
| 1. Target consistency | `CLI.checkTargetMatches` | `--target` equals the `targetBackend` field forwarded from the plan's imported prelude |
| 2. Structural + kind allowlist | `Dhall.validate` | Non-empty `targetBackend`, backend is known, every assertion has non-empty `kind`/`primaryKey`, `kind` is in the backend's allowlist |
| 3. Schema + conflicts | The emitter (Serverspec lives in `Emit/Serverspec.hs`) | Per-attribute type checking, fail-fast on contradictory writes to the same `(kind, primaryKey)`, layout collisions |
| 4. Path safety | `Layout.validateLayoutPath` | Reject absolute paths, `..`, leading separators, and control characters consistently across Posix/Windows |

**Practical consequence**: when you add a new Serverspec resource kind, you
update layer 3 (the emitter schema) only. Layer 2's allowlist auto-syncs
because `serverspecAllowedKinds` is derived from `serverspecSchema`'s keys —
no edits to `Dhall.validate` needed.

---

## 5. Per-module "what does changing this break?"

### 5.1 `PanInfraSpec.IR.*` (treat as a stable contract)

Defines `Node`, `Selector`, `Assertion`, `Mapping`, `PlanFile`, `Job`, and
`ExecutionPlan`. The whole point of the IR is **backend-agnosticism** —
Serverspec / InSpec / Ansible vocabulary must not appear here.

- Adding a field cascades into the in-file `FromDhall` decoder, the matching
  `dhall/*.dhall` schema, and every backend emitter.
- `SelAnd` / `SelOr` / `SelNot` are **constructed from Haskell only**
  (Dhall lacks recursive types). The CLI's `--only-*` chaining uses them
  internally; they have no Dhall surface.
- `IR/Expr.hs` (`Expr`) is the typed sub-IR that escape-hatch patterns
  (`ALRubyExpr`) graduate into when they recur often enough to deserve a
  first-class constructor. Embedded inside `AttrLeaf` via `ALExpr`. Stays
  flat (non-recursive) for the same Dhall-no-recursive-types reason as
  `Selector`. Grow additively — see issue #57.
- `IR/SourceLoc.hs` (`SourceLoc`) carries Dhall source-file coordinates
  (file, line, col, raw text) for an IR node. `Assertion` keeps a list of
  these in `aSourceLocs` so the Serverspec emitter can prepend
  `# src: <file>:<line>:<col> — <expr>` comments above each `describe`
  block. The list grows when `mergeGroup` collapses redundant assertions
  for the same `(kind, primaryKey)` — every contributor's location is
  preserved.

### 5.2 `PanInfraSpec.Dhall`

Loaders for inventory and plan files plus layer-2 validate.
`backendAllowedKinds` and `knownBackends` are *re-exports* of values
derived from the `Emit` registry — no edits needed when adding a backend.

`loadPlan` is split: a partial normaliser
(`PanInfraSpec.Dhall.SourceMap.betaReduceKeepNotes`) runs on the
resolved expression — it performs β-reduction, `let` inlining,
field projection, record `//` merge, and `List/fold` while preserving
every `Note s` so the AST walker (`extractAssertionLocs`) can capture
each assertion's location. Then `Dhall.normalize` + `Dhall.extract`
decode the value side, and `attachLocs` splices the locations back in
by their `(mappingIdx, assertionIdx)`. Standard `Dhall.normalize` would
discard `Note`, so we cannot use it for the location pass. The plan can
be authored in any of the natural shapes — direct record literal,
`Plan.make`/`Plan.onAll`/`Plan.forRole`/`Plan.forTag`/`Plan.forHost`,
or with `Spec.module_` wrapping a list — and per-assertion locations
will still surface.

### 5.3 `PanInfraSpec.Resolve`

`matches` (selector semantics) and `resolve` (Inventory × Plan →
ExecutionPlan). When you add a new selector constructor, watch the
exhaustiveness of `matches` — `-Werror=incomplete-patterns` will catch
omissions, but only after you remember to add the case.

### 5.4 `PanInfraSpec.Layout`

Owns output path decisions and path validation. It does **not** own
auxiliary file paths (Rakefile, helpers, hosts, …) — those belong to the
Scaffold.

- A new `Sharing` mode requires extending the `insertSpec` branches inside
  every emitter.
- Loosening path validation (leading separator, `..`, control characters,
  Posix/Windows duality) changes behavior across CI runners — review carefully.

### 5.5 `PanInfraSpec.Scaffold`

Owns the **runner-adjacent files** a backend wants alongside the per-host
specs (Rakefile, spec_helper.rb, ansible_spec's `hosts` and `site.yml`, …).
Three supply routes:

| Route | Source | Use case |
|---|---|---|
| `sStaticFiles` | Plain text fields in Dhall (prefer `./path as Text`) | Inventory-independent, fixed files |
| `sDerivedFiles` | A Dhall function `\(nodes : List Inventory.Node) -> ...` | Trivial inventory-derived files |
| `sBuiltinDerivers` | Haskell-side renderers picked by a `BuiltinDeriver` tag | Derivations awkward in Dhall (e.g. role-deduplicated INI) |

**Invariant**: the `Scaffold` Haskell type stays **backend-agnostic**.
Serverspec-flavoured vocabulary like "Rakefile" lives in the Dhall preludes
under `dhall/Scaffold/` and inside the corresponding emitter, never on the
Haskell type.

### 5.6 `PanInfraSpec.Emit` (the dispatcher)

The `registry :: Map Text BackendEntry` in this module is the **single
source of truth** for which backends this build knows about:

```haskell
registry :: Map Text BackendEntry
registry = Map.fromList
  [ ("serverspec", Serverspec.serverspecBackend)
  ]
```

`knownBackends` and `backendAllowedKinds` are derived from it. Add a new
backend by adding *one* import and *one* row here; layer-2 validate, the
`--target` accept-list, and the dispatcher all sync automatically.

### 5.7 `PanInfraSpec.Emit.Backend`

Defines the emitter contract:

```haskell
type Emitter = Scaffold -> Layout -> ExecutionPlan -> Either Text (Map FilePath Text)
data BackendEntry = BackendEntry
  { beEmitter      :: Emitter
  , beAllowedKinds :: [Text]
  }
```

Each backend produces one `BackendEntry` and registers it via the registry
above.

### 5.8 `PanInfraSpec.Emit.Serverspec`

The reference and currently sole backend. `serverspecSchema` (the per-kind
allowed-attributes table) is the seed for both layer-3 validation and
layer-2 `beAllowedKinds`. Adding a new Serverspec resource means editing
`serverspecSchema` and writing the corresponding renderer in this file.

### 5.9 `PanInfraSpec.SoT`

Adapter typeclass turning external sources into `[Node]`. Phase 4 ships
only the Terraform tfstate adapter under `PanInfraSpec.SoT.Terraform`. To
add a new adapter, define the `SoT` instance, then wire a new constructor
into `CLI.InventorySource` and a new `--from-<adapter>` flag.

### 5.10 `PanInfraSpec.CLI`

Owns `Options`, the optparse-applicative parser, and `run`. **All IO is
confined here and to `app/Main.hs`** by project convention; library
modules below stay pure.

---

## 6. Extension-point checklists

### 6.1 Add a new backend

1. Add a Dhall prelude under `dhall/<Backend>.dhall` with smart
   constructors so unsound combinations are rejected at parse time.
2. Add `src/PanInfraSpec/Emit/<Backend>.hs` exporting:
   - `<backend>Schema :: Map Text [(Text, AttrTag)]`
   - `<backend>AllowedKinds :: [Text]` (the schema's keys)
   - `emit :: Emitter`
   - `<backend>Backend :: BackendEntry`
3. Add one import and one entry to `registry` in
   `src/PanInfraSpec/Emit.hs`. **That alone** wires up layer-2 validate
   and the `--target` accept-list.
4. Tests:
   - Extend `test/Unit/RegistryTest.hs` style coverage (known backends /
     allowlist).
   - Drop a minimal end-to-end sample under `test/Golden/<backend>/`.
   - Add a property test under `test/Property/` if there are structural
     invariants worth checking.
5. Update `docs/architecture.md` (the planned-backends sentence) and this
   guide.

### 6.2 Add a new Serverspec kind / attribute

1. Add a smart constructor (and any new union types) to
   `dhall/Serverspec.dhall`.
2. Extend `serverspecSchema` in `src/PanInfraSpec/Emit/Serverspec.hs`,
   then implement the corresponding `formatXxx` renderer.
3. If a golden fixture under `test/Golden/expected/` needs to change,
   regenerate it intentionally and explain the diff in the PR body.
4. Update `docs/resources.md` (the user-facing catalogue).

### 6.3 Add a new SoT adapter

1. Implement `instance SoT MyAdapter` under
   `src/PanInfraSpec/SoT/<Adapter>.hs`.
2. Add a new constructor to `CLI.InventorySource` and a
   `--from-<adapter>` branch in `inventorySourceP` (single-token flag —
   optparse-applicative cannot dispatch on a previous flag's value).
3. Extend the `loadNodes` pattern match.
4. Add `test/SoT/<Adapter>Test.hs` and register it in `test/Spec.hs`.

### 6.4 Extend Layout

Adding a third `Sharing` mode beyond `PerHost` / `PerRole`:

- Update `Sharing` and its `FromDhall` instance in `Layout.hs`, and the
  union in `dhall/Layout.dhall`.
- Cover the new case in every emitter's `insertSpec`.
  `-Werror=incomplete-patterns` will catch omissions.
- Remember this is backend-agnostic: every existing backend is affected.

### 6.5 Extend Scaffold

Adding a new built-in deriver:

- Add a `BuiltinDeriver` constructor and update its `FromDhall` instance.
- Extend the matching union in `dhall/Scaffold.dhall`.
- Cover the new case in `resolveBuiltinDerivers`.
- Implement the renderer in Haskell (see `renderAnsibleHostsIni` /
  `renderAnsibleSiteYml` for the shape).

---

## 7. Test layout

`test/Spec.hs` is the tasty entry point. Tests are split into:

| Group | Location | Purpose |
|---|---|---|
| Unit | `test/Unit/*.hs` | Per-function behavior (validate, layout checks, scaffold, registry, IR split, module split, custom attribute expansion) |
| Roundtrip | `test/Roundtrip/DhallEncodingTest.hs` | Dhall encode/decode round-trip equality (sanity for IR encoders) |
| Property | `test/Property/EmitTest.hs` | QuickCheck-driven structural invariants of the emitter |
| Synth | `test/Synth/HundredHostsTest.hs` | Large synthetic inventories |
| SoT | `test/SoT/TerraformTest.hs` | Terraform state adapter |
| Golden (flat / by_role / ansible_spec) | `test/Spec.hs` + `test/Golden/` | End-to-end byte-for-byte fixtures |

`test/Golden/expected/` is **LF-only**. When regenerating fixtures on
Windows, double-check `core.autocrlf=false` so line endings don't drift
(see `CONTRIBUTING.md`).

Regenerate goldens with `--accept`, then *eyeball the diff* before
committing:

```sh
cabal test paninfraspec-test --test-options='--accept'
```

Run a single group:

```sh
cabal test paninfraspec-test --test-options='-p "Unit.Layout"'
cabal test paninfraspec-test --test-options='-p "golden (ansible_spec scaffold)"'
```

---

## 8. CLI flags and exit codes

| Flag | Required | Purpose |
|---|---|---|
| `--inventory PATH` / `--from-terraform-state PATH` | One required, mutually exclusive | Inventory source |
| `--plan PATH` | yes | Plan file |
| `--target BACKEND` | yes | Output backend (currently only `serverspec`) |
| `--out DIR` | yes | Output directory (created if missing) |
| `--layout PATH` | no | Custom layout (omit for `defaultLayout`) |
| `--scaffold PATH` | no | Custom scaffold (omit for `defaultServerspecScaffold`) |
| `--only-role` / `--only-host` / `--only-tag` | no | Pre-filter on inventory; multiple flags AND together |
| `--dump-plan` | no | Print the resolved `ExecutionPlan` as a tree and skip file output |
| `--version` / `-V` | no | Print the version |

Exit codes:
- `0` — success.
- `2` — every kind of failure (load, validate, layout/scaffold resolution,
  emit, write). Errors land on stderr in the form
  `paninfraspec-gen: <stage>: <reason>`.

For the user-facing CLI reference, see [`docs/cli.md`](./cli.md).

---

## 9. Project invariants

> Use this checklist before opening a PR. Violations are typically a sign a
> change belongs in a different module.

| Invariant | How it's enforced / verified |
|---|---|
| `PanInfraSpec.IR.*` carries no backend-specific vocabulary | Code review; grep for backend-flavored strings outside `Emit.<Backend>` |
| Adding a backend is one new import + one registry row | Existing backend tests pass unchanged |
| Layer-2 allowlist is derived from emitter schema | `Unit.RegistryTest` compares `knownBackends` / `backendAllowedKinds` against the registry |
| Library code is pure — IO lives only in `CLI` and `Main` | No `IO` imports in `IR`, `Resolve`, `Layout`, `Scaffold`, `Emit*`, `DumpPlan` |
| Path validation is consistent on both Posix and Windows rules | `Unit.LayoutTest` |
| `--target` mismatch with the plan's `targetBackend` exits with code 2 | `Unit.ValidateTest`-style coverage |
| `-Wall -Werror` and the extra warning flags must not be silenced | CI's `cabal build` |

---

## 10. See also

- [`docs/architecture.md`](./architecture.md) — high-level pipeline diagram and backend extension policy
- [`docs/cli.md`](./cli.md) — user-facing CLI reference
- [`docs/inventory.md`](./inventory.md) / [`docs/plan.md`](./plan.md) — Dhall input authoring
- [`docs/layout.md`](./layout.md) / [`docs/scaffold.md`](./scaffold.md) — output layout and scaffolds
- [`docs/resources.md`](./resources.md) — Serverspec resource catalogue
- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — workflow, conventions, PR rules
