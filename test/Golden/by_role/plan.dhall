let Spec = ../../../dhall/Serverspec.dhall

let Plan = ../../../dhall/Plan.dhall

in  Plan.make Spec.targetBackend
      [ Plan.onAll
          [ Spec.command "uname -a" (Spec.CommandState.ExitCode 0) ]
      , Plan.forRole "Web"
          [ Spec.port 80 Spec.PortState.Listening ]
      , Plan.forRole "DBPrimary"
          [ Spec.port 5432 Spec.PortState.Listening ]
      ]
