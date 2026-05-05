# Writing a plan

A plan pairs a target backend with a list of `Mapping` values. Each mapping
pairs a *selector* with a list of *assertions*, and a node receives every
assertion from every mapping whose selector matches it.

## Selectors

See [`examples/plan.dhall`](../examples/plan.dhall):

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

## Provenance comments

When `paninfraspec-gen` is invoked without `--no-source-comments` (the
default), the emitter prepends a `# src:` line above every generated
`describe` block that points back to the originating Dhall expression:

```ruby
# src: examples/plan.dhall:24:17 — Spec.package "nginx" Spec.PackageState.Installed
describe package('nginx') do
  it { should be_installed }
end
```

When several assertions merge into one `describe` block (e.g. `OwnedBy` and
`Mode` for the same file), one `# src:` line per origin is emitted so each
contributing Dhall location is preserved. Failing Serverspec tests can then
be traced back to the responsible Dhall expression by file, line, and
column.

The walker that captures these locations runs a small partial normaliser
of its own (β-reduction, `let` inlining, field projection, list `//`
record-merge, and `List/fold`) that preserves every `Note` wrapper, so
plans authored with `Plan.make`, `Plan.onAll`, `Plan.forRole`,
`Plan.forTag`, `Plan.forHost`, and `Spec.module_` produce `# src:`
comments transparently — there is no need to rewrite plans as raw
record literals to get provenance trace.

### Surfacing locations in `rake spec` output

`# src:` comments only show up when someone opens the generated file. To
push the same information into RSpec's *runtime* output — the failure
summary CI logs, the lines `rake spec` prints to the terminal — pass
`--source-loc-in-describe`. The emitter then appends the location to each
`describe` block's secondary description string:

```ruby
describe package('nginx'), '(examples/plan.dhall:24:17)' do
  it { should be_installed }
end
```

`rake spec` prints:

```
Package "nginx" (examples/plan.dhall:24:17)
  is expected to be installed
```

When several assertions merge into one `describe` block, every
contributing location is comma-joined inside the secondary string
(`'(plan.dhall:42:7, plan.dhall:55:9)'`). The flag is off by default
because it changes the human-readable test output that downstream CI
tooling may parse; opt in once your environment is ready.

## Splitting a host's spec into multiple files

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

See [`examples/plan-with-modules.dhall`](../examples/plan-with-modules.dhall)
for a complete example.

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

**Step 2: reference it from the plan.** PanInfraSpec offers two paths —
prefer the typed one when the pattern fits.

### Typed expression path (preferred)

```dhall
-- Pin to a tag and `dhall freeze` for production use.
let Spec = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Serverspec.dhall

in  Spec.mysqlConfig "innodb_buffer_pool_size"
      ( Spec.MysqlConfigState.CompareTypedExpr
          { op    = Spec.CompareOp.Ge
          , value = Spec.factIntScaled "total_ram_kb" [1024, 70] 100
          }
      )
```

`factIntScaled "n" [m1, m2, ...] d` renders as
`paninfraspec_n.to_i * m1 * m2 ... / d`; the unary `factInt "n"` renders
as `paninfraspec_n.to_i`. Both live in the typed sub-IR
(`Spec.Expr`) and are checked by Dhall — typos in the multipliers or
divisor are caught at parse time, not at spec run time. `CompareTypedExpr`
is available on `MysqlConfigState` and `PhpConfigState`;
`X509CertificateState` exposes the same shape as
`ValidityInDaysCompareTypedExpr`.

The sub-IR also covers binary arithmetic over a flat `Operand`
(numeric literal or host fact reference):

| Helper | Renders to |
|---|---|
| `Spec.factInt "n"`                       | `paninfraspec_n.to_i` |
| `Spec.factIntScaled "n" [m1, m2] d`      | `paninfraspec_n.to_i * m1 * m2 / d` |
| `Spec.percentOf p "n"`                   | `paninfraspec_n.to_i * p / 100` (sugar for `factIntScaled "n" [p] 100`) |
| `Spec.exprAdd (Spec.opFact "a") (Spec.opFact "b")` | `paninfraspec_a.to_i + paninfraspec_b.to_i` |
| `Spec.exprSub (Spec.opFact "t") (Spec.opLit 50)`   | `paninfraspec_t.to_i - 50` |
| `Spec.exprMul (Spec.opLit 2) (Spec.opFact "x")`    | `2 * paninfraspec_x.to_i` |
| `Spec.exprDiv (Spec.opFact "n") (Spec.opLit 4)`    | `paninfraspec_n.to_i / 4` |

`opLit` / `opFact` are the two `Operand` constructors. The binary
constructors take `Operand` (not `Expr`) on both sides because Dhall
lacks recursive types — to compose more than two terms, use
`factIntScaled` for the `fact * lit * ... / lit` shape, or fall back to
the escape hatch.

### Escape hatch (`CompareExpr` + `expand_attr`)

For patterns the typed sub-IR does not yet cover, fall back to embedding a
raw Ruby fragment:

```dhall
in  Spec.mysqlConfig "innodb_buffer_pool_size"
      ( Spec.MysqlConfigState.CompareExpr
          { op    = Spec.CompareOp.Gt
          , value =
              Spec.expand_attr "total_ram_kb" ++ ".to_i * 1024 * 70 / 100"
          }
      )
```

`Spec.expand_attr "<name>"` is the only place the `paninfraspec_` prefix
appears — the generator owns it and may rename it; your plans never need
to hard-code the prefix string. The `value : Text` field is emitted **as
bare Ruby**, so you can chain `.to_i`/`.to_f` and use arithmetic
operators. The existing `Compare` (`Natural`) variants stay available for
static thresholds. For Ruby expressions in contexts other than the three
`*ConfigState` types, use `AttrLeaf.ALRubyExpr` directly — that is the
underlying constructor everything else (`expand_attr`, `CompareExpr`) is
sugar on top.

**Both paths produce the same Ruby.** The typed and escape-hatch
snippets above generate byte-identical assertions:

```ruby
describe mysql_config('innodb_buffer_pool_size') do
  its(:value) { should be >= paninfraspec_total_ram_kb.to_i * 1024 * 70 / 100 }
end
```

### Escape-hatch policy

The `ALRubyExpr` / `expand_attr` / `CompareExpr` family is a deliberate
escape hatch, not the recommended path. If you find yourself reaching
for it repeatedly for the same shape of expression, that is a signal to
file an issue requesting a first-class typed constructor (see
[issue #57](https://github.com/ikaro1192/PanInfraSpec/issues/57)) — the
typed sub-IR grows additively as recurring patterns are observed.

**Out of scope.** PanInfraSpec does not statically check that a
`paninfraspec_<name>` token in a `value` string actually resolves to a
declared `customAttribute` — an undefined reference fails at spec
runtime with `NameError`. Use `expand_attr` / `factInt` / `factIntScaled`
(rather than hand-writing the prefix) to keep typos visible in code
review.
