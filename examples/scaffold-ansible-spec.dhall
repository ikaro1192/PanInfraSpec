-- examples/scaffold-ansible-spec.dhall
-- Re-exports the shipped ansible_spec scaffold without modification. Use
-- this as the starting point when you want to fork it: import
-- `dhall/Scaffold/AnsibleSpec.dhall` and override `staticFiles` (e.g. to
-- swap in your own Rakefile) using Dhall's record-update syntax (`//`).
--
-- Run the example with:
--
--   cabal run paninfraspec-gen -- \
--     --inventory examples/inventory-ansible-spec.dhall \
--     --plan      examples/plan-with-modules.dhall \
--     --target    serverspec \
--     --layout    examples/layout-ansible-spec.dhall \
--     --scaffold  examples/scaffold-ansible-spec.dhall \
--     --out       /tmp/ansible-out

../dhall/Scaffold/AnsibleSpec.dhall
