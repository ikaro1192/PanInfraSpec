# Writing an inventory

An inventory tells PanInfraSpec which nodes exist. You can write it by hand
in Dhall, or derive it from a Terraform state file.

## Dhall inventory

A Dhall inventory returns a `List Inventory.Node`. See
[`examples/inventory.dhall`](../examples/inventory.dhall):

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
| `customAttributes` | List of `{ name, command }` pairs run on the host at spec time and bound to a Ruby variable so plans can compare against per-host dynamic values. See [Per-host dynamic expected values](./plan.md#per-host-dynamic-expected-values). Pass `[] : List I.CustomAttribute` if you don't need any. |

## From Terraform state

Instead of hand-writing an inventory, point `--from-terraform-state` at a
`terraform.tfstate` JSON file:

```sh
paninfraspec-gen \
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
