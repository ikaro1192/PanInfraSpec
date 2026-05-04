# CLI reference

```
Usage: paninfraspec-gen (--inventory PATH | --from-terraform-state PATH)
                        --plan PATH --target BACKEND --out DIR
                        [--layout PATH] [--scaffold PATH]
                        [--only-role ROLE] [--only-host HOST] [--only-tag TAG]
                        [--dump-plan]
```

## Flags

- `--inventory PATH` — Dhall file returning `List Inventory.Node`.
- `--from-terraform-state PATH` — Terraform state JSON; `aws_instance`
  resources become nodes. Mutually exclusive with `--inventory`. See
  [`inventory.md`](./inventory.md#from-terraform-state).
- `--plan PATH` — Dhall file returning `List Plan.Mapping`.
- `--target BACKEND` — currently only `serverspec`. Goss, InSpec, and
  Testinfra emitters are planned; each will ship with its own Dhall prelude
  and become a new value here.
- `--out DIR` — output directory (created if missing).
- `--layout PATH` — optional Dhall layout file (returns `Layout.Layout`).
  When omitted, files are written flat as `<hostname>_spec.rb` (and
  `<hostname>_<module>_spec.rb` when `Spec.module_` is used). See
  [`layout.md`](./layout.md).
- `--scaffold PATH` — optional Dhall scaffold file (returns
  `Scaffold.Scaffold`). When omitted, the built-in Serverspec scaffold is
  used. See [`scaffold.md`](./scaffold.md).
- `--only-role ROLE` / `--only-host HOST` / `--only-tag TAG` — filter the
  inventory before resolution. Multiple flags are AND-composed.
- `--dump-plan` — print the resolved plan as a tree and exit; no files are
  written. Useful for confirming which mappings hit which nodes.

## Exit codes

- `0` — success.
- `2` — any error (Dhall parse, validation, write failure, unknown backend,
  etc.).

There is no `1` because PanInfraSpec does not execute tests — those failures
are surfaced by Serverspec itself.
