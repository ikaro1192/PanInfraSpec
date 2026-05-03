-- examples/layout-ansible-spec.dhall
-- v2 layout matching the ansible_spec gem convention:
--   spec/<group>/<module>_spec.rb   when a module label is set
--   spec/<group>/<hostname>_spec.rb when no module label is set
--
-- The `spec/` prefix is what the shipped ansible_spec Rakefile globs
-- against (`spec/<group>/*_spec.rb`).

let L = ../dhall/Layout.dhall

in  L.ansibleSpec
