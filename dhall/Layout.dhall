-- dhall/Layout.dhall
-- Output-layout prelude. The user supplies a function
-- @Node -> Optional Text -> Text@ for the per-host (and optionally
-- per-module) spec path. The Haskell side decodes 'specPath' via
-- 'Dhall.function' and applies it once per (node, module) bucket.
--
-- Why a function rather than a template string: organisations diverge wildly
-- in how they want to lay out specs (flat, by role, by tag, by environment)
-- and Dhall's let-bindings + interpolation give the full expressive power
-- needed without us inventing a template DSL.
--
-- The auxiliary file paths (Rakefile, spec_helper.rb, ...) are owned by the
-- scaffold (see dhall/Scaffold.dhall), not by the layout.
--
-- Sharing modes
--   PerHost  Each (node, module) maps to a distinct file. specPath MUST be
--            injective over the inventory: two hosts in the same role + module
--            cannot collapse to the same path or emit fails fast.
--   PerRole  A specPath that hostname-erases (e.g. `${role}/${module}_spec.rb`)
--            is interpreted as a role-shared spec. Multiple hosts in the same
--            role are merged into a single output file when their generated
--            content matches; per-host runs are expected to come from the
--            scaffold-side runner (e.g. ansible_spec's Rakefile sets
--            TARGET_HOST per host). `customAttributes` are host-specific and
--            therefore rejected at emit time in PerRole mode.

let I = ./Inventory.dhall

let Sharing : Type = < PerHost | PerRole >

let Layout : Type =
      { specPath : I.Node -> Optional Text -> Text
      , sharing  : Sharing
      }

-- | Construct a PerHost layout (default). Existing callers that wrote
--   `L.make { specPath = ... }` keep working bit-for-bit because the
--   sharing field is filled in for them.
let make
    : { specPath : I.Node -> Optional Text -> Text } -> Layout
    = \(x : { specPath : I.Node -> Optional Text -> Text }) ->
        { specPath = x.specPath, sharing = Sharing.PerHost }

-- | Construct a PerRole layout. Use this when the specPath collapses
--   the hostname (e.g. `${role}/${module}_spec.rb`) and you intend the
--   spec file to be shared across every host in the role. The runner
--   (Rakefile / CI) is then responsible for iterating hosts via
--   TARGET_HOST or an equivalent mechanism.
let makePerRole
    : { specPath : I.Node -> Optional Text -> Text } -> Layout
    = \(x : { specPath : I.Node -> Optional Text -> Text }) ->
        { specPath = x.specPath, sharing = Sharing.PerRole }

-- A common layout: <role>/<module>_spec.rb when a module is present,
-- falling back to <role>/<hostname>_spec.rb when it is not. This is a
-- PerRole layout: when a module label is set the path drops the hostname,
-- so multiple hosts in the same role share `<role>/<module>_spec.rb`. The
-- shipped Serverspec scaffold's Rakefile runs each spec for every host in
-- the role via TARGET_HOST, so the role-shared file is the expected shape.
let byGroupProduct
    : Layout
    = makePerRole
        { specPath =
            \(n : I.Node) ->
            \(m : Optional Text) ->
              merge
                { Some = \(name : Text) -> "${n.role}/${name}_spec.rb"
                , None = "${n.role}/${n.hostname}_spec.rb"
                }
                m
        }

-- A layout matching the ansible_spec gem convention:
-- `spec/<group>/<module>_spec.rb` when a module label is set,
-- `spec/<group>/<hostname>_spec.rb` otherwise. The `spec/` prefix is what
-- the shipped ansible_spec Rakefile globs against. PerRole because the
-- shipped Rakefile (`dhall/Scaffold/AnsibleSpec/Rakefile.template`)
-- iterates the hosts file per role and reuses the same spec file for
-- every host in that role.
let ansibleSpec
    : Layout
    = makePerRole
        { specPath =
            \(n : I.Node) ->
            \(m : Optional Text) ->
              merge
                { Some = \(name : Text) -> "spec/${n.role}/${name}_spec.rb"
                , None = "spec/${n.role}/${n.hostname}_spec.rb"
                }
                m
        }

in  { Layout         = Layout
    , Sharing        = Sharing
    , make           = make
    , makePerRole    = makePerRole
    , byGroupProduct = byGroupProduct
    , ansibleSpec    = ansibleSpec
    }
