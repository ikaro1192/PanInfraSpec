-- examples/inventory-ansible-spec.dhall
-- Inventory for the ansible_spec scaffold example. The shipped
-- ansible_spec layout writes `spec/<group>/<module>_spec.rb`, which is a
-- PerRole layout: every host in the group shares the same spec file and
-- the Rakefile (`Scaffold/AnsibleSpec/Rakefile.template`) iterates the
-- hosts via TARGET_HOST. So you can list multiple hosts per role here
-- without triggering specPath collisions.
--
-- Note: PerRole layouts reject `customAttributes` because those are
-- per-host runtime values that cannot live in a role-shared spec. Use
-- the default (PerHost) layout if you need them.

let I = ../dhall/Inventory.dhall

in  [ { hostname         = "web01"
      , ip               = Some "10.0.1.10"
      , role             = "Web"
      , tags             = [ "frontend" ]
      , customAttributes = [] : List I.CustomAttribute
      }
    , { hostname         = "web02"
      , ip               = Some "10.0.1.11"
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
