let Spec = ../../dhall/Serverspec.dhall

let Plan = ../../dhall/Plan.dhall

in  Plan.make Spec.targetBackend
      [ Plan.onAll
          [ Spec.command "uname -a" (Spec.CommandState.ExitCode 0)
          , Spec.package "nginx" Spec.PackageState.Installed
          , Spec.service "nginx" Spec.ServiceState.Running
          , Spec.service "nginx" Spec.ServiceState.Enabled
          , Spec.port 80 (Spec.PortState.WithProtocol "tcp")
          , Spec.file "/etc/nginx/nginx.conf" Spec.FileState.Exist
          , Spec.file "/var/log/nginx" (Spec.FileState.OwnedBy "nginx")
          , Spec.file "/var/log/nginx" (Spec.FileState.Mode 644)
          , Spec.file "/etc/profile" (Spec.FileState.Contains "PATH")
          , Spec.user "nginx" Spec.UserState.Exist
          , Spec.user "nginx" (Spec.UserState.HasUid 101)
          , Spec.user "nginx" (Spec.UserState.BelongsToGroup "nginx")
          , Spec.user "nginx" (Spec.UserState.HasHomeDirectory "/var/lib/nginx")
          , Spec.user "nginx" (Spec.UserState.HasLoginShell "/usr/sbin/nologin")
          , Spec.group "nginx" Spec.GroupState.Exist
          , Spec.group "nginx" (Spec.GroupState.HasGid 101)
          , Spec.process "nginx" Spec.ProcessState.Running
          , Spec.process "nginx" (Spec.ProcessState.RunByUser "nginx")
          , Spec.mount "/data" Spec.MountState.Mounted
          , Spec.mount "/data" (Spec.MountState.OnDevice "/dev/sda1")
          , Spec.mount "/data" (Spec.MountState.OfFstype "ext4")
          , Spec.interface "eth0" Spec.InterfaceState.Exist
          , Spec.interface "eth0" (Spec.InterfaceState.HasSpeed 1000)
          , Spec.interface "eth0" (Spec.InterfaceState.HasIpv4Address "10.0.1.10")
          , Spec.kernelModule "br_netfilter" Spec.KernelModuleState.Loaded
          ]
      ]
