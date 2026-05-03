-- examples/plan.dhall
-- Mapping rules: every node gets a baseline check; Web nodes get an nginx stack;
-- anything tagged "metrics" gets a Prometheus port check.

-- The two imports below resolve to the latest `main` of this repository.
-- For production use, pin to a release tag (e.g. v0.2.0.0) and run
-- `dhall freeze` to attach an integrity SHA-256 hash to each import.
let Spec = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Serverspec.dhall

let Plan = https://raw.githubusercontent.com/ikaro1192/PanInfraSpec/main/dhall/Plan.dhall

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

-- DBPrimary nodes: assert that MySQL's innodb_buffer_pool_size is at least
-- 70% of the host's total RAM. The threshold is per-host and resolved on the
-- target via the customAttribute "total_ram_kb" declared in
-- examples/inventory.dhall; `Spec.expand_attr` keeps plans free of the
-- generator's `paninfraspec_` prefix.
--
-- Note: a single primaryKey can carry only one bound on `value`, so this
-- example expresses the lower bound only. To enforce "between 70% and 80%",
-- combine both checks in the host-side script and assert ExitCode 0 on a
-- `command` instead.
let mysqlSpec
    : List Spec.Assertion
    = [ Spec.mysqlConfig "innodb_buffer_pool_size"
          ( Spec.MysqlConfigState.CompareExpr
              { op    = Spec.CompareOp.Ge
              , value =
                  Spec.expand_attr "total_ram_kb"
                    ++ ".to_i * 1024 * 70 / 100"
              }
          )
      ]

in  Plan.make Spec.targetBackend
      [ Plan.onAll baseSpec
      , Plan.forRole "Web" nginxSpec
      , Plan.forRole "DBPrimary" mysqlSpec
      , Plan.forTag "metrics" [ Spec.port 9090 Spec.PortState.Listening ]
      ]
