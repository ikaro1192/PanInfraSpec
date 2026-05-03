-- dhall/Inventory.dhall
-- Backend-agnostic prelude for the inventory.

let Role = Text  -- organisations have different role vocabularies; keep as Text wrapper

let CustomAttribute =
      { name    : Text
      , command : Text
      }

let Node =
      { hostname         : Text
      , ip               : Optional Text
      , role             : Role
      , tags             : List Text
      , customAttributes : List CustomAttribute
      }

in  { Role             = Role
    , CustomAttribute  = CustomAttribute
    , Node             = Node
    }
