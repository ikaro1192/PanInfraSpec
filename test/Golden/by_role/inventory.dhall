let I = ../../../dhall/Inventory.dhall

in  [ { hostname = "web01"
      , ip       = Some "10.0.1.10"
      , role     = "Web"
      , tags     = [ "frontend" ]
      }
    , { hostname = "db01"
      , ip       = None Text
      , role     = "DBPrimary"
      , tags     = [ "metrics" ]
      }
    ]
  : List I.Node
