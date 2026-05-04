let I = ../../../dhall/Inventory.dhall

let L = ../../../dhall/Layout.dhall

in  L.make
      { specPath =
          \(n : I.Node) ->
          \(_ : Optional Text) ->
            "${n.role}/${n.hostname}_spec.rb"
      }
