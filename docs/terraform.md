# Loading inventory from Terraform state

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
