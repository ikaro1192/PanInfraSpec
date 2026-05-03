let Spec = ../../../dhall/Serverspec.dhall

let Plan = ../../../dhall/Plan.dhall

in  Plan.make Spec.targetBackend
      [ Plan.forRole "Web"
          ( Spec.module_ "nginx"
              [ Spec.package "nginx" Spec.PackageState.Installed
              , Spec.service "nginx" Spec.ServiceState.Running
              , Spec.port 80 Spec.PortState.Listening
              ]
          )
      , Plan.forRole "Web"
          ( Spec.module_ "php"
              [ Spec.package "php-fpm" Spec.PackageState.Installed
              , Spec.service "php-fpm" Spec.ServiceState.Running
              ]
          )
      , Plan.forRole "DBPrimary"
          ( Spec.module_ "mysql"
              [ Spec.package "mysql-server" Spec.PackageState.Installed
              , Spec.service "mysqld"       Spec.ServiceState.Running
              , Spec.port    3306           Spec.PortState.Listening
              ]
          )
      ]
