let I = ../../dhall/Inventory.dhall

in  [ { hostname         = "web01"
      , ip               = Some "10.0.1.10"
      , role             = "Web"
      , tags             = [ "frontend", "metrics" ]
      , customAttributes =
          [ { name = "total_ram_kb",   command = "awk '/MemTotal/ {print \$2}' /proc/meminfo" }
          , { name = "max_mem_mb",     command = "echo 256" }
          , { name = "min_cert_days",  command = "echo 30" }
          ]
      }
    ]
  : List I.Node
