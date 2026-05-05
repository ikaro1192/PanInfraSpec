-- examples/plan-typed-expr.dhall
-- Same shape as examples/plan.dhall, but the per-host MySQL threshold is
-- expressed via the typed expression IR (`Spec.factIntScaled`) instead of
-- a string-embedded Ruby fragment (`Spec.expand_attr ++ ".to_i ..."`).
--
-- Both forms generate byte-identical Ruby; the typed form just keeps the
-- Dhall side type-checkable.

let Spec = ../dhall/Serverspec.dhall

let Plan = ../dhall/Plan.dhall

let baseSpec
    : List Spec.Assertion
    = [ Spec.command "uname -a" (Spec.CommandState.ExitCode 0) ]

let nginxSpec
    : List Spec.Assertion
    = [ Spec.package "nginx" Spec.PackageState.Installed
      , Spec.service "nginx" Spec.ServiceState.Running
      , Spec.service "nginx" Spec.ServiceState.Enabled
      , Spec.port 80 (Spec.PortState.WithProtocol "tcp")
      , Spec.file "/etc/nginx/nginx.conf" Spec.FileState.Exist
      , Spec.file "/var/log/nginx" (Spec.FileState.OwnedBy "nginx")
      , Spec.file "/var/log/nginx" (Spec.FileState.Mode 644)
      , Spec.user "nginx" Spec.UserState.Exist
      , Spec.process "nginx" Spec.ProcessState.Running
      ]

-- DBPrimary nodes: three typed-expression patterns side by side.
--
-- (1) innodb_buffer_pool_size >= 70% of total RAM (in bytes).
--     `factIntScaled "total_ram_kb" [1024, 70] 100` renders to
--     `paninfraspec_total_ram_kb.to_i * 1024 * 70 / 100` — byte-identical
--     to the escape-hatch form in examples/plan.dhall.
-- (2) max_connections <= max_clients - 50 (`exprSub` over two operands).
-- (3) thread_cache_size eq max_clients / 4 (`exprDiv` over two operands).
let mysqlSpec
    : List Spec.Assertion
    = [ Spec.mysqlConfig "innodb_buffer_pool_size"
          ( Spec.MysqlConfigState.CompareTypedExpr
              { op    = Spec.CompareOp.Ge
              , value = Spec.factIntScaled "total_ram_kb" [1024, 70] 100
              }
          )
      , Spec.mysqlConfig "max_connections"
          ( Spec.MysqlConfigState.CompareTypedExpr
              { op    = Spec.CompareOp.Le
              , value = Spec.exprSub (Spec.opFact "max_clients") (Spec.opLit 50)
              }
          )
      , Spec.mysqlConfig "thread_cache_size"
          ( Spec.MysqlConfigState.CompareTypedExpr
              { op    = Spec.CompareOp.Eq
              , value = Spec.exprDiv (Spec.opFact "max_clients") (Spec.opLit 4)
              }
          )
      ]

in  Plan.make Spec.targetBackend
      [ Plan.onAll baseSpec
      , Plan.forRole "Web" nginxSpec
      , Plan.forRole "DBPrimary" mysqlSpec
      , Plan.forTag "metrics" [ Spec.port 9090 Spec.PortState.Listening ]
      ]
