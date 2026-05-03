-- dhall/Layout.dhall
-- Output-layout prelude. The user supplies a function @Node -> Text@ for the
-- per-host spec path, and fixed strings for the shared helper / Rakefile
-- paths. The Haskell side decodes 'specPath' via 'Dhall.function' and applies
-- it once per node.
--
-- Why a function rather than a template string: organisations diverge wildly
-- in how they want to lay out specs (flat, by role, by tag, by environment)
-- and Dhall's let-bindings + interpolation give the full expressive power
-- needed without us inventing a template DSL.

let I = ./Inventory.dhall

let Layout : Type =
      { specPath     : I.Node -> Text
      , helperPath   : Text
      , rakefilePath : Text
      }

let make
    : Layout -> Layout
    = \(x : Layout) -> x

let flat
    : Layout
    = { specPath     = \(n : I.Node) -> "${n.hostname}_spec.rb"
      , helperPath   = "spec_helper.rb"
      , rakefilePath = "Rakefile"
      }

let byRole
    : Layout
    = { specPath     = \(n : I.Node) -> "${n.role}/${n.hostname}_spec.rb"
      , helperPath   = "spec_helper.rb"
      , rakefilePath = "Rakefile"
      }

in  { Layout = Layout
    , make   = make
    , flat   = flat
    , byRole = byRole
    }
