# How it works

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
