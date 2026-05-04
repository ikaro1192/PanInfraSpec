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
