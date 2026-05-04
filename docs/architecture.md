# Architecture: how backends plug in

```
Dhall preludes  ──►  Generic Semantic IR  ──►  per-backend emitter  ──►  out/<host>_spec.rb
```

The Dhall preludes use smart constructors so unsound combinations (e.g.
`service "nginx" PackageState.Installed`) are rejected at parse time. The
generator collects all assertions sharing a `(kind, primaryKey)` into one
`describe` block; if two assertions disagree on an attribute value (e.g.
`exit-status = 0` and `exit-status = 1` for the same command), generation
fails fast rather than emit Ruby that is guaranteed to fail at run time.

The arrow above is drawn for Serverspec, but the IR and the emitter
interface are backend-agnostic. Adding a new backend is a new Dhall
prelude plus a new emitter module — no changes to existing inputs, the
IR, or other emitters. The dispatcher in
[`src/PanInfraSpec/Emit.hs`](../src/PanInfraSpec/Emit.hs) routes on
`--target`, and
[`src/PanInfraSpec/Emit/Serverspec.hs`](../src/PanInfraSpec/Emit/Serverspec.hs)
is the reference implementation. InSpec is the next backend planned.
