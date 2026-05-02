-- examples/plan.dhall
-- Mapping rules: every node gets a baseline check; Web nodes get an nginx stack;
-- anything tagged "metrics" gets a Prometheus port check.

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

in  Plan.make Spec.targetBackend
      [ Plan.onAll baseSpec
      , Plan.forRole "Web" nginxSpec
      , Plan.forTag "metrics" [ Spec.port 9090 Spec.PortState.Listening ]
      ]
