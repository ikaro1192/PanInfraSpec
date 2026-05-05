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

The IR also carries a small typed expression sub-IR (`PanInfraSpec.IR.Expr`)
that plugs into `AttrLeaf` via `ALExpr`. It promotes the most common
escape-hatch patterns (per-host arithmetic such as memory %) into typed,
backend-agnostic constructors so plans can avoid embedding raw Ruby strings;
each backend emitter renders these into its own target language. The set is
intentionally narrow and grows additively as recurring `ALRubyExpr` patterns
are observed (see GitHub issue #57).

The arrow above is drawn for Serverspec, but the IR and the emitter
interface are backend-agnostic. Adding a new backend is a new Dhall
prelude plus a new emitter module — no changes to existing inputs, the
IR, or other emitters. The registry in
[`src/PanInfraSpec/Emit.hs`](../src/PanInfraSpec/Emit.hs) maps
`--target` to a `BackendEntry` (emitter + allowed-kinds list); wiring up
a new backend is one new import and one new entry in that map.
[`src/PanInfraSpec/Emit/Serverspec.hs`](../src/PanInfraSpec/Emit/Serverspec.hs)
is the reference implementation, exporting `serverspecBackend ::
BackendEntry`. The same registry is the canonical source for
`knownBackends` and `backendAllowedKinds`, so layer-2 validation in
[`src/PanInfraSpec/Dhall.hs`](../src/PanInfraSpec/Dhall.hs) and
the dispatch in `emitFor` cannot drift apart. InSpec is the next
backend planned.

## Source-location threading

The plan loader runs a small AST walker
([`src/PanInfraSpec/Dhall/SourceMap.hs`](../src/PanInfraSpec/Dhall/SourceMap.hs))
over the resolved Dhall expression, capturing the `Note Src` wrapping
each assertion. The captured locations are spliced back into the decoded
`Assertion` values via `aSourceLocs`, which the Serverspec emitter then
renders as `# src:` comments above the corresponding `describe` block.

`Dhall.Core.normalize` strips `Note` wrappers, so the walker cannot use
it directly. Instead it runs a small partial normaliser
(`betaReduceKeepNotes`) that performs β-reduction, `let` inlining,
record-field projection, record `//` merge, and `List/fold` step-by-step
while threading every `Note s e` through unchanged. That covers the
smart-constructor library shipped in `dhall/Plan.dhall` and
`dhall/Serverspec.dhall` (`Plan.make`, `Plan.onAll`, `Plan.forRole`,
`Plan.forTag`, `Plan.forHost`, `Spec.module_`), so plan files authored
in the natural smart-constructor style still expose per-assertion
locations. The value side still goes through the standard
`Dhall.normalize` + `Dhall.extract` pipeline. See
[`docs/plan.md`](./plan.md#provenance-comments) for the user-visible
behaviour.
