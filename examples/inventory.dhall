-- examples/inventory.dhall
-- Sample inventory: 3 nodes. db01 has no IP to exercise Optional Text round-trip.

-- Resolves to the latest `main` of this repository.
-- For production use, pin to a release tag (e.g. v0.2.0.0) and run
-- `dhall freeze` to attach an integrity SHA-256 hash to this import.
let I = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Inventory.dhall

in  [ { hostname         = "web01"
      , ip               = Some "10.0.1.10"
      , role             = "Web"
      , tags             = [ "frontend", "metrics" ]
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
      , customAttributes =
          -- Per-host facts referenced by the bundled example plans.
          --
          --   * `total_ram_kb` — RAM in KiB, used by examples/plan.dhall
          --     and examples/plan-typed-expr.dhall to size
          --     `innodb_buffer_pool_size` relative to this host's actual
          --     RAM. Bound as `paninfraspec_total_ram_kb` in the
          --     generated db01_spec.rb.
          --
          --   * `max_clients` — application-defined upper bound on
          --     concurrent clients, exercised by the typed-expression
          --     `exprSub` / `exprDiv` examples in
          --     examples/plan-typed-expr.dhall. Replace the placeholder
          --     command with whatever fits your environment.
          [ { name    = "total_ram_kb"
            , command = "awk '/MemTotal/ {print \$2}' /proc/meminfo"
            }
          , { name    = "max_clients"
            , command = "echo 200"
            }
          ]
      }
    ]
  : List I.Node
