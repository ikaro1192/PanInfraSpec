-- examples/inventory-ansible-spec.dhall
-- Focused inventory for the ansible_spec scaffold example. The shipped
-- ansible_spec layout writes `spec/<group>/<module>_spec.rb`, which means
-- two hosts in the same group + module would collide on the same file.
-- Real-world ansible_spec deployments solve this at the runner level: one
-- spec file per (group, module) is parameterised over `TARGET_HOST` at
-- rake time. PanInfraSpec emits one job per host, so for now keep
-- ansible_spec inventories at one host per role; use plain Serverspec for
-- many-hosts-per-role inventories.

let I = ../dhall/Inventory.dhall

in  [ { hostname         = "web01"
      , ip               = Some "10.0.1.10"
      , role             = "Web"
      , tags             = [ "frontend" ]
      , customAttributes = [] : List I.CustomAttribute
      }
    , { hostname         = "db01"
      , ip               = None Text
      , role             = "DBPrimary"
      , tags             = [ "metrics" ]
      , customAttributes = [] : List I.CustomAttribute
      }
    ]
  : List I.Node
