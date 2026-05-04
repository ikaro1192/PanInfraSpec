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

### From a release asset

Pre-built `paninfraspec-gen` binaries are published on every tag at
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

### From source

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

## Choosing a scaffold

The *scaffold* owns the auxiliary files that wrap the per-host spec files —
`Rakefile`, `spec_helper.rb`, and any inventory-derived inventory files
(e.g. ansible_spec's `hosts` and `site.yml`). The default is `serverspec`;
pass `--scaffold PATH` to load a different one.

| Scaffold | Recommended layout | Extra files emitted |
|---|---|---|
| `dhall/Scaffold/Serverspec.dhall` (default) | default flat or `L.byGroupProduct` | `Rakefile`, `spec_helper.rb` |
| `dhall/Scaffold/AnsibleSpec.dhall` | `L.ansibleSpec` | `Rakefile`, `spec_helper.rb`, `hosts`, `site.yml` |

```sh
cabal run paninfraspec-gen -- \
  --inventory examples/inventory-ansible-spec.dhall \
  --plan      examples/plan-with-modules.dhall \
  --target    serverspec \
  --layout    examples/layout-ansible-spec.dhall \
  --scaffold  examples/scaffold-ansible-spec.dhall \
  --out       /tmp/ansible-out
```

A scaffold is just a Dhall record with `staticFiles`, `derivedFiles`, and
`builtinDerivers` — fork the shipped one and override individual files via
`//`. See [`examples/scaffold-custom.dhall`](./examples/scaffold-custom.dhall)
for the smallest possible fork (swap the Rakefile body, keep everything
else) and [`docs/scaffold.md`](./docs/scaffold.md) for the full reference.

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

### Splitting a host's spec into multiple files

Tag a list of assertions with `Spec.module_ "<name>"` to label them with a
product or component. The generator partitions a single host's assertions
across multiple spec files keyed off the label — e.g. `Web/nginx_spec.rb`
and `Web/php_spec.rb` instead of one combined `Web/web01_spec.rb` —
provided the layout's `specPath` actually uses the module argument
(`L.byGroupProduct` and `L.ansibleSpec` do; layouts that ignore it will
collapse modules back into one file).

```dhall
Plan.forRole "Web"
  ( Spec.module_ "nginx"
      [ Spec.package "nginx" Spec.PackageState.Installed
      , Spec.service "nginx" Spec.ServiceState.Running
      ]
  )
```

See [`examples/plan-with-modules.dhall`](./examples/plan-with-modules.dhall)
for a complete example.

## Loading inventory from Terraform state

Instead of hand-writing an inventory, point `--from-terraform-state` at a
`terraform.tfstate` JSON file and PanInfraSpec will derive nodes from every
`aws_instance` resource. See [`docs/terraform.md`](./docs/terraform.md) for
the tag conventions and a full example.

## Customising the output layout

By default each node lands at `<hostname>_spec.rb` directly under `--out`
(and `<hostname>_<module>_spec.rb` if you tagged assertions with
`Spec.module_`). If you want a different shape — say one directory per
role — write a Dhall layout file and pass it with `--layout`. The shipped
prelude provides two ready-made layouts:

- `L.byGroupProduct` — `<role>/<module>_spec.rb` when a module label is
  set, `<role>/<hostname>_spec.rb` otherwise.
- `L.ansibleSpec` — `spec/<role>/<module>_spec.rb` / `spec/<role>/<hostname>_spec.rb`,
  matching the [ansible_spec gem's](https://github.com/volanja/ansible_spec)
  Rakefile expectations.

Or roll your own:

```dhall
-- Pin to a tag and `dhall freeze` for production use.
let I = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Inventory.dhall
let L = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Layout.dhall

in  L.make
      { specPath =
          \(n : I.Node) ->
          \(m : Optional Text) ->
            merge
              { Some = \(name : Text) -> "${n.role}/${name}_spec.rb"
              , None = "${n.role}/${n.hostname}_spec.rb"
              }
              m
      }
```

`specPath` is a `Node -> Optional Text -> Text` function. The first
argument is the inventory node; the second is the optional module label
set via `Spec.module_` in the plan. The generator applies it once per
(node, module) bucket.

Paths are validated: empty, absolute (`/etc/passwd`), and traversing
(`..`) results are rejected, and a `specPath` that maps two buckets to the
same file fails fast rather than silently overwriting.

Auxiliary file paths (`spec_helper.rb`, `Rakefile`, ansible_spec's `hosts`
and `site.yml`) are owned by the scaffold, not the layout — see "Choosing
a scaffold" above.

## CLI reference

```
Usage: paninfraspec-gen --inventory PATH --plan PATH --target BACKEND --out DIR
                        [--layout PATH] [--scaffold PATH]
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
  When omitted, files are written flat as `<hostname>_spec.rb` (and
  `<hostname>_<module>_spec.rb` when `Spec.module_` is used).
- `--scaffold PATH` — optional Dhall scaffold file (returns `Scaffold.Scaffold`).
  When omitted, the built-in Serverspec scaffold is used. See "Choosing a
  scaffold" above and [`docs/scaffold.md`](./docs/scaffold.md).
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
