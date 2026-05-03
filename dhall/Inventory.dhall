-- dhall/Inventory.dhall
-- Backend-agnostic prelude for the inventory.

let Role = Text  -- organisations have different role vocabularies; keep as Text wrapper

let Node =
      { hostname : Text
      , ip       : Optional Text
      , role     : Role
      , tags     : List Text
      }

in  { Role = Role
    , Node = Node
    }
