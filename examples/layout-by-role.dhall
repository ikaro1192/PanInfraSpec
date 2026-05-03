-- examples/layout-by-role.dhall
-- Pass this file via @--layout examples/layout-by-role.dhall@ to land each
-- node's spec at @<role>/<hostname>_spec.rb@ rather than at the top of the
-- output directory.

let L = ../dhall/Layout.dhall

in  L.byRole
