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

-- v2 Layout: the specPath function takes both the node and an optional
-- module label (set via `Spec.module_` in the plan) so a single host can
-- produce multiple spec files. v2 layouts do not carry helperPath /
-- rakefilePath — the placement of auxiliary files is owned by the
-- scaffold (see dhall/Scaffold.dhall).
let LayoutV2 : Type =
      { specPath : I.Node -> Optional Text -> Text
      }

let makeV2
    : LayoutV2 -> LayoutV2
    = \(x : LayoutV2) -> x

-- A common v2 layout: <role>/<module>_spec.rb when a module is present,
-- falling back to <role>/<hostname>_spec.rb when it is not. This is the
-- recommended shape for the ansible_spec scaffold, but works fine with the
-- default Serverspec scaffold too.
let byGroupProduct
    : LayoutV2
    = { specPath =
          \(n : I.Node) ->
          \(m : Optional Text) ->
            merge
              { Some = \(name : Text) -> "${n.role}/${name}_spec.rb"
              , None = "${n.role}/${n.hostname}_spec.rb"
              }
              m
      }

-- A v2 layout matching the ansible_spec gem convention:
-- `spec/<group>/<module>_spec.rb` when a module label is set,
-- `spec/<group>/<hostname>_spec.rb` otherwise. The `spec/` prefix is what
-- the shipped ansible_spec Rakefile globs against.
let ansibleSpec
    : LayoutV2
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
    , flat           = flat
    , byRole         = byRole
    , LayoutV2       = LayoutV2
    , makeV2         = makeV2
    , byGroupProduct = byGroupProduct
    , ansibleSpec    = ansibleSpec
    }
