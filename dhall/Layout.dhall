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

let I = ./Inventory.dhall

let Layout : Type =
      { specPath : I.Node -> Optional Text -> Text
      }

let make
    : Layout -> Layout
    = \(x : Layout) -> x

-- A common layout: <role>/<module>_spec.rb when a module is present,
-- falling back to <role>/<hostname>_spec.rb when it is not. Recommended
-- shape for the default Serverspec scaffold once you start using
-- `Spec.module_` to split a host's spec into multiple files.
let byGroupProduct
    : Layout
    = { specPath =
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
-- the shipped ansible_spec Rakefile globs against.
let ansibleSpec
    : Layout
    = { specPath =
          \(n : I.Node) ->
          \(m : Optional Text) ->
            merge
              { Some = \(name : Text) -> "spec/${n.role}/${name}_spec.rb"
              , None = "spec/${n.role}/${n.hostname}_spec.rb"
              }
              m
      }

in  { Layout         = Layout
    , make           = make
    , byGroupProduct = byGroupProduct
    , ansibleSpec    = ansibleSpec
    }
