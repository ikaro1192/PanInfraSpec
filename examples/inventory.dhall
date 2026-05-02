-- examples/inventory.dhall
-- Sample inventory: 3 nodes. db01 has no IP to exercise Optional Text round-trip.

let I = ../dhall/Inventory.dhall

in  [ { hostname = "web01"
      , ip = Some "10.0.1.10"
      , role = "Web"
      , tags = [ "frontend", "metrics" ]
      }
    , { hostname = "web02"
      , ip = Some "10.0.1.11"
      , role = "Web"
      , tags = [ "frontend" ]
      }
    , { hostname = "db01"
      , ip = None Text
      , role = "DBPrimary"
      , tags = [ "metrics" ]
      }
    ]
  : List I.Node
