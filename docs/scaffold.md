# Scaffolds

A *scaffold* owns the auxiliary files that wrap the per-host spec files —
the Rakefile, the spec helper, and any inventory-derived inventory files
(e.g. ansible_spec's `hosts` and `site.yml`). A scaffold is decoupled from
the *target backend* (`--target serverspec`, future `--target inspec`)
and decoupled from the *output layout* (`--layout`), so the three axes
compose freely.

PanInfraSpec ships two scaffolds out of the box:

| File | Identifier | Use case |
|---|---|---|
| `dhall/Scaffold/Serverspec.dhall` | `serverspec` | Plain Serverspec; matches pre-0.3 behaviour bit-for-bit when `--scaffold` is omitted. |
| `dhall/Scaffold/AnsibleSpec.dhall` | `ansible_spec` | Drive Serverspec via the [ansible_spec gem](https://github.com/volanja/ansible_spec); inventory comes from a generated `hosts` INI and `site.yml`. |

Pass one with `--scaffold PATH`. When the flag is omitted, the built-in
Serverspec scaffold is used.

## The Dhall record

```dhall
let Scaffold : Type =
      { name            : Text
      , staticFiles     : List OutputFile
      , derivedFiles    : List Inventory.Node -> List OutputFile
      , builtinDerivers : List BuiltinDeriver
      }
```

| Field | Purpose |
|---|---|
| `name` | Identifier surfaced in error messages. |
| `staticFiles` | Inventory-independent files. The Serverspec scaffold ships its `Rakefile` and `spec_helper.rb` here. |
| `derivedFiles` | A Dhall function from the resolved node list to extra files. Use this when you can express the rendering in pure Dhall. |
| `builtinDerivers` | Escape hatch for renderings that would be awkward in Dhall (text equality, INI parsing, etc.). Each entry names a shipped Haskell renderer plus the path it should land at. The shipped variants today are `AnsibleHostsIni` and `AnsibleSiteYml`. |

`OutputFile` is `{ path : Text, content : Text }`. The path is relative
to `--out`; the content is plain `Text`. To pull a Rakefile body out of a
sibling text file rather than embedding it as a Dhall multi-line literal,
use Dhall's `as Text` import:

```dhall
{ path = "Rakefile", content = ./Rakefile.template as Text }
```

## Forking a shipped scaffold

The minimum-viable fork imports the shipped scaffold and overrides one
field:

```dhall
-- examples/scaffold-custom.dhall
let serverspec = ../dhall/Scaffold/Serverspec.dhall

in  serverspec
      // { staticFiles =
              [ { path    = "Rakefile",       content = ./my-rakefile.template      as Text }
              , { path    = "spec_helper.rb", content = ./my-spec-helper.template as Text }
              ]
          }
```

To add a custom inventory-derived file, drop a Dhall function into
`derivedFiles`:

```dhall
serverspec
  // { derivedFiles =
         \(nodes : List Inventory.Node) ->
           [ { path    = "MANIFEST"
             , content =
                 List/fold
                   Inventory.Node nodes Text
                   (\(n : Inventory.Node) -> \(acc : Text) -> "${n.hostname}\n${acc}")
                   ""
             }
           ]
     }
```

If your derivation needs Text equality, set comprehensions, or other
operations that are awkward in pure Dhall, prefer one of the shipped
`builtinDerivers` (or open an issue requesting a new variant) over
hand-rolling them.

## ansible_spec specifics

The shipped ansible_spec scaffold:

- Generates `hosts` as INI with one `[<role>]` section per distinct role.
  The role name is used verbatim as the Ansible group name; tag-derived
  groups are out of scope (fork the scaffold if you need them).
- Generates `site.yml` with one `- hosts: <role>` entry per distinct role
  and an empty `roles:` list. The shipped Rakefile globs
  `spec/<group>/*_spec.rb` directly per group, so the playbook only needs
  to surface the group, not enumerate roles.
- Maps PanInfraSpec's module label (`Spec.module_ "nginx" […]`) to a per-
  group spec file under `spec/<group>/<module>_spec.rb`. Use the shipped
  `L.ansibleSpec` layout to get this path shape; the Rakefile globs that
  shape directly.

### Multiple hosts in the same group

The shipped `L.ansibleSpec` layout writes `spec/<group>/<module>_spec.rb`
without including the hostname. When two hosts share both group and
module, both jobs emit to the same path and the CLI fails with a
collision error. ansible_spec the gem solves this at the runner level
(one spec file per (group, module), parameterised over `TARGET_HOST` at
rake time), but the PanInfraSpec emitter is per-host today. Until per-
group de-duplication lands, keep ansible_spec inventories at one host
per role, or fork the layout to include `${n.hostname}` in the path.
