# CLI reference

```
Usage: paninfraspec-gen (--inventory PATH | --from-terraform-state PATH)
                        --plan PATH --target BACKEND --out DIR
                        [--layout PATH] [--scaffold PATH]
                        [--only-role ROLE] [--only-host HOST] [--only-tag TAG]
                        [--dump-plan] [--no-source-comments]
                        [--source-loc-in-describe]
```

## Flags

- `--inventory PATH` — Dhall file returning `List Inventory.Node`.
- `--from-terraform-state PATH` — Terraform state JSON; `aws_instance`
  resources become nodes. Mutually exclusive with `--inventory`. See
  [`inventory.md`](./inventory.md#from-terraform-state).
- `--plan PATH` — Dhall file returning `List Plan.Mapping`.
- `--target BACKEND` — selects which emitter renders the spec files.
  Backends are pluggable: today only `serverspec` is wired up, but the
  architecture supports adding more without core changes (see
  [`architecture.md`](./architecture.md)). InSpec is the next backend
  planned; it will appear here as a new value once its emitter and Dhall
  prelude ship.
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
- `--no-source-comments` — suppress the `# src: <plan>:<line>:<col> — <expr>`
  provenance comments that the emitter prepends above each generated
  `describe` block. Use this for byte-stable output (e.g. when the spec
  files are diffed in CI). Comments are on by default. See
  [`plan.md`](./plan.md#provenance-comments).
- `--source-loc-in-describe` — append the Dhall source location to each
  `describe` block's secondary description string, so RSpec runtime output
  (e.g. `rake spec`) prints the originating plan line next to the resource
  name. Off by default because it changes RSpec output strings that
  downstream CI tooling may parse. Whereas `# src:` comments only show up
  when someone opens the generated file, this flag surfaces the location in
  test failure logs. See [`plan.md`](./plan.md#provenance-comments).

## Exit codes

- `0` — success.
- `2` — any error (Dhall parse, validation, write failure, unknown backend,
  etc.).

There is no `1` because PanInfraSpec does not execute tests — those failures
are surfaced by Serverspec itself.
