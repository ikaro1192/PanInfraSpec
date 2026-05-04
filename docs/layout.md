# Customising the output layout

By default each node lands at `<hostname>_spec.rb` directly under `--out`
(and `<hostname>_<module>_spec.rb` if you tagged assertions with
`Spec.module_`). If you want a different shape — say one directory per
role — write a Dhall layout file and pass it with `--layout`.

The shipped prelude provides two ready-made layouts:

- `L.byGroupProduct` — `<role>/<module>_spec.rb` when a module label is
  set, `<role>/<hostname>_spec.rb` otherwise. **PerRole** (see below).
- `L.ansibleSpec` — `spec/<role>/<module>_spec.rb` /
  `spec/<role>/<hostname>_spec.rb`, matching the
  [ansible_spec gem's](https://github.com/volanja/ansible_spec) Rakefile
  expectations. **PerRole** (see below).

## PerHost vs PerRole

A layout declares how multiple hosts in the same role collapse onto
output files:

- **PerHost** (default; `L.make { specPath = ... }`) — every (node, module)
  pair must map to a distinct file. The generator fails fast if `specPath`
  is non-injective. Required when nodes carry `customAttributes`, since
  those are per-host runtime values rendered into a host-specific preamble.
- **PerRole** (`L.makePerRole { ... }`, also `L.byGroupProduct`,
  `L.ansibleSpec`) — a `specPath` that drops the hostname (e.g.
  `${role}/${module}_spec.rb`) is intended to be a role-shared file.
  Multiple hosts in the same role merge into a single file when their
  generated content matches; differing content fails. Per-host execution
  is expected to come from the runner (the shipped ansible_spec Rakefile
  iterates the inventory and sets `TARGET_HOST` per host). PerRole layouts
  reject any node with non-empty `customAttributes`.

## Rolling your own

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
and `site.yml`) are owned by the **scaffold**, not the layout — see
[`scaffold.md`](./scaffold.md).
