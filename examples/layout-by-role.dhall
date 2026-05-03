-- examples/layout-by-role.dhall
-- Pass this file via @--layout examples/layout-by-role.dhall@ to land each
-- node's spec at @<role>/<hostname>_spec.rb@ rather than at the top of the
-- output directory.

-- Resolves to the latest `main` of this repository.
-- For production use, pin to a release tag (e.g. v0.2.0.0) and run
-- `dhall freeze` to attach an integrity SHA-256 hash to this import.
let L = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Layout.dhall

in  L.byRole
