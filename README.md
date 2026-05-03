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
cabal build
```

This produces the `paninfraspec-gen` executable. After it is built you only
ever interact with Dhall files and the CLI — no Haskell knowledge required.

## Quickstart

```sh
cabal run paninfraspec-gen -- \
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

## Writing an inventory

An inventory is a Dhall file that returns a list of nodes. See
[`examples/inventory.dhall`](./examples/inventory.dhall):

```dhall
-- Pin to a tag and `dhall freeze` for production use.
let I = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Inventory.dhall

let none = [] : List I.CustomAttribute

in  [ { hostname = "web01", ip = Some "10.0.1.10", role = "Web",       tags = [ "frontend", "metrics" ], customAttributes = none }
    , { hostname = "web02", ip = Some "10.0.1.11", role = "Web",       tags = [ "frontend" ],            customAttributes = none }
    , { hostname = "db01",  ip = None Text,        role = "DBPrimary", tags = [ "metrics" ],             customAttributes = none }
    ] : List I.Node
```

Each node has five fields:

| Field | Meaning |
|---|---|
| `hostname` | Used as the spec filename (`<hostname>_spec.rb`) and for `--only-host` filtering. |
| `ip` | Optional. Recorded for your own reference; transport is configured via `TARGET_HOST` at run time. |
| `role` | Free-form text. Selectors target nodes by role. |
| `tags` | Free-form labels. A node can carry any number; selectors can target any one. |
| `customAttributes` | List of `{ name, command }` pairs. Each one is run on the host at spec time and bound to a Ruby variable so plans can compare against per-host dynamic values. See [Per-host dynamic expected values](#per-host-dynamic-expected-values). Pass `[] : List I.CustomAttribute` if you don't need any. |

## Writing a plan

A plan pairs a target backend with a list of `Mapping` values. Each mapping
pairs a *selector* with a list of *assertions*, and a node receives every
assertion from every mapping whose selector matches it. See
[`examples/plan.dhall`](./examples/plan.dhall):

```dhall
-- Pin to a tag and `dhall freeze` for production use.
let Spec = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Serverspec.dhall
let Plan = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Plan.dhall

let baseSpec  = [ Spec.command "uname -a" (Spec.CommandState.ExitCode 0) ]
let nginxSpec =
      [ Spec.package "nginx" Spec.PackageState.Installed
      , Spec.service "nginx" Spec.ServiceState.Running
      , Spec.service "nginx" Spec.ServiceState.Enabled
      , Spec.port 80 (Spec.PortState.WithProtocol "tcp")
      ]

in  Plan.make Spec.targetBackend
      [ Plan.onAll                     baseSpec
      , Plan.forRole "Web"             nginxSpec
      , Plan.forTag  "metrics"         [ Spec.port 9090 Spec.PortState.Listening ]
      ]
```

The four selector helpers are:

| Helper | Matches |
|---|---|
| `Plan.onAll xs` | every node |
| `Plan.forRole "R" xs` | nodes whose `role` equals `"R"` |
| `Plan.forTag "T" xs` | nodes whose `tags` contain `"T"` |
| `Plan.forHost "H" xs` | the node whose `hostname` equals `"H"` |

Mappings stack: a `Web`-role node tagged `metrics` in the example above
receives the baseline check, the full nginx stack, *and* the Prometheus port.

## Loading inventory from Terraform state

Instead of hand-writing an inventory, point `--from-terraform-state` at a
`terraform.tfstate` JSON file and PanInfraSpec will derive nodes from every
`aws_instance` resource. See [`docs/terraform.md`](./docs/terraform.md) for
the tag conventions and a full example.

## Customising the output layout

By default each node lands at `<hostname>_spec.rb` directly under `--out`. If
you want a different layout — say one directory per role — write a Dhall
layout file and pass it with `--layout`:

```dhall
-- examples/layout-by-role.dhall
-- Pin to a tag and `dhall freeze` for production use.
let L = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Layout.dhall
in  L.byRole   -- spec files under <role>/<hostname>_spec.rb
```

Or roll your own with the full Dhall expression power:

```dhall
-- Pin to a tag and `dhall freeze` for production use.
let I = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Inventory.dhall
let L = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Layout.dhall

in  L.make
      { specPath = \(n : I.Node) ->
          "${n.role}/${n.hostname}_spec.rb"
      , helperPath   = "spec_helper.rb"
      , rakefilePath = "Rakefile"
      }
```

`specPath` is a `Node -> Text` function; the generator applies it once per
node. Paths are validated: empty, absolute (`/etc/passwd`), and traversing
(`..`) results are rejected, and a `specPath` that maps two hosts to the same
file fails fast rather than silently overwriting.

`spec_helper.rb` and `Rakefile` are co-located with the spec files; the
generated `Rakefile` globs `*_spec.rb` in its own directory, so if you nest
specs into subdirectories you may need a `Rakefile` per directory. The
prelude ships `L.flat` (the default) and `L.byRole` ready-made.

## CLI reference

```
Usage: paninfraspec-gen --inventory PATH --plan PATH --target BACKEND --out DIR
                        [--layout PATH]
                        [--only-role ROLE] [--only-host HOST] [--only-tag TAG]
                        [--dump-plan]
```

- `--inventory PATH` — Dhall file returning `List Inventory.Node`.
- `--from-terraform-state PATH` — Terraform state JSON; `aws_instance`
  resources become nodes. Use instead of `--inventory`, not in addition to it.
- `--plan PATH` — Dhall file returning `List Plan.Mapping`.
- `--target BACKEND` — currently only `serverspec`. Goss, InSpec, and
  Testinfra emitters are planned; each will ship with its own Dhall prelude
  and become a new value here.
- `--out DIR` — output directory (created if missing).
- `--layout PATH` — optional Dhall layout file (returns `Layout.Layout`).
  When omitted, files are written flat as `<hostname>_spec.rb`.
- `--only-role ROLE` / `--only-host HOST` / `--only-tag TAG` — filter the
  inventory before resolution. Multiple flags are AND-composed.
- `--dump-plan` — print the resolved plan as a tree and exit; no files are
  written. Useful for confirming which mappings hit which nodes.

Exit codes: `0` on success, `2` on any error (Dhall parse, validation, write
failure, unknown backend, etc.). There is no `1` because PanInfraSpec does
not execute tests — those failures are surfaced by Serverspec itself.

## Resource catalogue

PanInfraSpec ships smart constructors for 26 Serverspec resource types
(service, package, port, file, user, iptables, SELinux, cgroup, …). Each
constructor takes a primary key plus a state value drawn from a typed union.

See [`docs/resources.md`](./docs/resources.md) for the full table of
constructors, their state unions, and how to add a new resource.

## Per-host dynamic expected values

Some assertions only make sense relative to a per-host runtime value — for
example "MySQL's `innodb_buffer_pool_size` must be 70-80% of the host's total
RAM". You can express this without falling back to raw shell by combining
`Inventory.customAttributes` with the `CompareExpr` state on `mysql_config`,
`php_config`, and `x509_certificate`.

**Step 1: declare the per-host command in the inventory.**

```dhall
{ hostname         = "db01"
, ip               = Some "10.0.2.10"
, role             = "DBPrimary"
, tags             = [ "metrics" ]
, customAttributes =
    [ { name    = "total_ram_kb"
      , command = "awk '/MemTotal/ {print $2}' /proc/meminfo"
      }
    ]
}
```

The generator binds each `customAttribute` to a Ruby variable at the top of
that host's spec file:

```ruby
require 'spec_helper'

paninfraspec_total_ram_kb = Specinfra.backend.run_command("awk '/MemTotal/ {print $2}' /proc/meminfo").stdout.strip
```

`name` must be a valid Ruby local-variable identifier
(`^[a-z_][a-zA-Z0-9_]*$`); duplicates within the same host and empty
names/commands are rejected at generate time.

**Step 2: reference it from the plan with `expand_attr`.**

```dhall
-- Pin to a tag and `dhall freeze` for production use.
let Spec = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Serverspec.dhall

in  Spec.mysqlConfig "innodb_buffer_pool_size"
      ( Spec.MysqlConfigState.CompareExpr
          { op    = Spec.CompareOp.Gt
          , value =
              Spec.expand_attr "total_ram_kb" ++ ".to_i * 1024 * 70 / 100"
          }
      )
```

`Spec.expand_attr "<name>"` is the only place the `paninfraspec_` prefix
appears — the generator owns it and may rename it; your plans never need to
hard-code the prefix string. The generated assertion is:

```ruby
describe mysql_config('innodb_buffer_pool_size') do
  its(:value) { should be > paninfraspec_total_ram_kb.to_i * 1024 * 70 / 100 }
end
```

`CompareExpr` is available on `MysqlConfigState`, `PhpConfigState`, and
`X509CertificateState` (as `ValidityInDaysCompareExpr`). The `value : Text`
field is emitted **as bare Ruby**, so you can chain `.to_i`/`.to_f` and use
arithmetic operators. The existing `Compare` (`Natural`) variants stay
available for static thresholds.

**Escape hatch.** If you need a Ruby expression in a context other than the
three `*ConfigState` types, use `AttrLeaf.ALRubyExpr` directly. That is the
underlying constructor; everything else (`expand_attr`, `CompareExpr`) is
sugar on top.

**Out of scope.** PanInfraSpec does not statically check that a
`paninfraspec_<name>` token in a `value` string actually resolves to a
declared `customAttribute` — an undefined reference fails at spec runtime
with `NameError`. Use `expand_attr` (rather than hand-writing the prefix) to
keep typos visible in code review.

## How it works

```
Dhall preludes  ──►  Generic Semantic AST  ──►  per-backend emitter  ──►  out/<host>_spec.rb
```

The Dhall preludes use smart constructors so unsound combinations (e.g.
`service "nginx" PackageState.Installed`) are rejected at parse time. The
generator collects all assertions sharing a `(kind, primaryKey)` into one
`describe` block; if two assertions disagree on an attribute value (e.g.
`exit-status = 0` and `exit-status = 1` for the same command), generation
fails fast rather than emit Ruby that is guaranteed to fail at run time.

The arrow above is drawn for Serverspec, but the AST and the emitter
interface are backend-agnostic — Goss (YAML), InSpec, and Testinfra emitters
are planned, and adding one is a new Dhall prelude plus a new emitter, with
no changes to existing inputs.

## See also

- [`docs/resources.md`](./docs/resources.md) — full Serverspec resource catalogue
- [`docs/terraform.md`](./docs/terraform.md) — loading inventory from a Terraform `tfstate` file
- [`examples/`](./examples) — sample inventory, plan, and Terraform state
- [`dhall/`](./dhall) — preludes you import from your own Dhall files
  (`Inventory.dhall`, `Serverspec.dhall`, `Plan.dhall`)
