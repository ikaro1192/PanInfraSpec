# PanInfraSpec
[![CI](https://github.com/ikaro1192/PanInfraSpec/actions/workflows/ci.yml/badge.svg)](https://github.com/ikaro1192/PanInfraSpec/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ikaro1192/PanInfraSpec)](https://github.com/ikaro1192/PanInfraSpec/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Haskell](https://img.shields.io/badge/language-Haskell-5D4F85)](https://www.haskell.org/)

PanInfraSpec is a typed front-end for [Serverspec](https://serverspec.org/).
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
let I = ../dhall/Inventory.dhall

in  [ { hostname = "web01", ip = Some "10.0.1.10", role = "Web",       tags = [ "frontend", "metrics" ] }
    , { hostname = "web02", ip = Some "10.0.1.11", role = "Web",       tags = [ "frontend" ] }
    , { hostname = "db01",  ip = None Text,        role = "DBPrimary", tags = [ "metrics" ] }
    ] : List I.Node
```

Each node has four fields:

| Field | Meaning |
|---|---|
| `hostname` | Used as the spec filename (`<hostname>_spec.rb`) and for `--only-host` filtering. |
| `ip` | Optional. Recorded for your own reference; transport is configured via `TARGET_HOST` at run time. |
| `role` | Free-form text. Selectors target nodes by role. |
| `tags` | Free-form labels. A node can carry any number; selectors can target any one. |

## Writing a plan

A plan is a list of `Mapping` values. Each mapping pairs a *selector* with a
list of *assertions*, and a node receives every assertion from every mapping
whose selector matches it. See [`examples/plan.dhall`](./examples/plan.dhall):

```dhall
let Spec = ../dhall/Serverspec.dhall
let Plan = ../dhall/Plan.dhall

let baseSpec  = [ Spec.command "uname -a" (Spec.CommandState.ExitCode 0) ]
let nginxSpec =
      [ Spec.package "nginx" Spec.PackageState.Installed
      , Spec.service "nginx" Spec.ServiceState.Running
      , Spec.service "nginx" Spec.ServiceState.Enabled
      , Spec.port 80 Spec.PortState.Listening
      ]

in  [ Plan.onAll                     baseSpec
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

Instead of hand-writing `examples/inventory.dhall`, point at a
`terraform.tfstate` JSON file:

```sh
cabal run paninfraspec-gen -- \
  --from-terraform-state examples/terraform-state.json \
  --plan                 examples/plan.dhall \
  --target               serverspec \
  --out                  /tmp/out
```

The Terraform adapter walks every `aws_instance` resource and applies the
following tag conventions:

| Field | Source | Fallback |
|---|---|---|
| `hostname` | `tags.Name` | `attributes.id`, then `<type>.<name>` |
| `ip` | `attributes.private_ip` | `attributes.public_ip`, then `None` |
| `role` | `tags.Role` | `"untagged"` |
| `tags` | remaining tag *values* (Name & Role excluded) | `[]` |

Other resource types (security groups, IAM, etc.) are skipped. Pass exactly
one of `--inventory` or `--from-terraform-state`, not both.

## CLI reference

```
Usage: paninfraspec-gen --inventory PATH --plan PATH --target BACKEND --out DIR
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
- `--only-role ROLE` / `--only-host HOST` / `--only-tag TAG` — filter the
  inventory before resolution. Multiple flags are AND-composed.
- `--dump-plan` — print the resolved plan as a tree and exit; no files are
  written. Useful for confirming which mappings hit which nodes.

Exit codes: `0` on success, `2` on any error (Dhall parse, validation, write
failure, unknown backend, etc.). There is no `1` because PanInfraSpec does
not execute tests — those failures are surfaced by Serverspec itself.

## Resource catalogue

The Dhall prelude in [`dhall/Serverspec.dhall`](./dhall/Serverspec.dhall)
exposes the following smart constructors. Each one takes a primary key (the
service name, port number, file path, etc.) and a state value drawn from the
matching `*State` union.

| Resource | Constructor | States |
|---|---|---|
| Service | `service : Text -> ServiceState -> Assertion` | `Running`, `Enabled` |
| Package | `package : Text -> PackageState -> Assertion` | `Installed` |
| Port | `port : Natural -> PortState -> Assertion` | `Listening`, `WithProtocol : Text` |
| Command | `command : Text -> CommandState -> Assertion` | `ExitCode : Natural` |
| File | `file : Text -> FileState -> Assertion` | `Exist`, `OwnedBy : Text`, `GroupedInto : Text`, `Mode : Natural`, `Contains : Text` |
| User | `user : Text -> UserState -> Assertion` | `Exist`, `HasUid : Natural`, `BelongsToGroup : Text`, `HasHomeDirectory : Text`, `HasLoginShell : Text` |
| Group | `group : Text -> GroupState -> Assertion` | `Exist`, `HasGid : Natural` |
| Process | `process : Text -> ProcessState -> Assertion` | `Running`, `RunByUser : Text` |
| Mount | `mount : Text -> MountState -> Assertion` | `Mounted`, `OnDevice : Text`, `OfFstype : Text` |
| Interface | `interface : Text -> InterfaceState -> Assertion` | `Exist`, `HasSpeed : Natural`, `HasIpv4Address : Text` |
| Kernel module | `kernelModule : Text -> KernelModuleState -> Assertion` | `Loaded` |
| Bond | `bond : Text -> BondState -> Assertion` | `Exist`, `HasInterface : Text` |
| Bridge | `bridge : Text -> BridgeState -> Assertion` | `Exist`, `HasInterface : Text` |
| Default gateway (singleton) | `defaultGateway : DefaultGatewayState -> Assertion` | `HasIpaddress : Text`, `HasInterface : Text` |
| Host | `host : Text -> HostState -> Assertion` | `Resolvable`, `Reachable`, `HasIpaddress : Text` |
| iptables | `iptables : Text -> IptablesState -> Assertion` | `HasRule : Text` |
| ip6tables | `ip6tables : Text -> Ip6tablesState -> Assertion` | `HasRule : Text` |
| ipfilter | `ipfilter : Text -> IpfilterState -> Assertion` | `HasRule : Text` |
| ipnat | `ipnat : Text -> IpnatState -> Assertion` | `HasRule : Text` |
| Routing table (singleton) | `routingTable : RoutingTableState -> Assertion` | `HasEntry : { destination : Text, gateway : Text }` |
| SELinux (singleton) | `selinux : SelinuxState -> Assertion` | `Enforcing`, `Permissive`, `Disabled` |
| SELinux module | `selinuxModule : Text -> SelinuxModuleState -> Assertion` | `Enabled`, `Installed` |
| Linux audit system (singleton) | `linuxAuditSystem : LinuxAuditSystemState -> Assertion` | `Running`, `Enabled` |
| Linux kernel parameter | `linuxKernelParameter : Text -> LinuxKernelParameterState -> Assertion` | `HasValue : Text` |
| Cgroup | `cgroup : Text -> CgroupState -> Assertion` | `HasParameter : { name : Text, value : Text }` |

To express more than one state for the same resource (e.g. nginx must be both
running and enabled), write two assertions with the same primary key — they
are merged into a single `describe` block in the generated Ruby.

To add a new resource, extend `dhall/Serverspec.dhall` with a smart
constructor and a state type, then add one entry to `formatItLine` in
`src/PanInfraSpec/Emit/Serverspec.hs` mapping each attribute key to its Ruby
DSL line.

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
no changes to existing inputs. The full design is in
[`specification.md`](./specification.md).

## See also

- [`specification.md`](./specification.md) — full design (~730 lines, JP/EN
  bilingual)
- [`examples/`](./examples) — sample inventory, plan, and Terraform state
- [`dhall/`](./dhall) — preludes you import from your own Dhall files
  (`Inventory.dhall`, `Serverspec.dhall`, `Plan.dhall`)
