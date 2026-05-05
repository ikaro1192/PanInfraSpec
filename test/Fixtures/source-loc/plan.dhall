-- Fixture for Unit.SourceLocTest. Uses an inline RecordLit so the AST walker
-- can pick up assertion-level Note Src entries without depending on
-- normalisation (which strips Note constructors).
let Spec = ../../../dhall/Serverspec.dhall

let Plan = ../../../dhall/Plan.dhall

in  { targetBackend = Spec.targetBackend
    , mappings =
        [ { selector = Plan.Selector.SelAll
          , assertions =
              [ Spec.command "uname -a" (Spec.CommandState.ExitCode 0)
              ]
          }
        , { selector = Plan.Selector.SelRole "Web"
          , assertions =
              [ Spec.package "nginx" Spec.PackageState.Installed
              , Spec.service "nginx" Spec.ServiceState.Running
              ]
          }
        ]
    }
