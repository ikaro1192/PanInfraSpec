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
          , Spec.bond "bond0" Spec.BondState.Exist
          , Spec.bond "bond0" (Spec.BondState.HasInterface "eth0")
          , Spec.bridge "br0" Spec.BridgeState.Exist
          , Spec.bridge "br0" (Spec.BridgeState.HasInterface "eth1")
          , Spec.defaultGateway (Spec.DefaultGatewayState.HasIpaddress "10.0.1.1")
          , Spec.defaultGateway (Spec.DefaultGatewayState.HasInterface "eth0")
          , Spec.host "example.jp" Spec.HostState.Resolvable
          , Spec.host "example.jp" Spec.HostState.Reachable
          , Spec.host "example.jp" (Spec.HostState.HasIpaddress "192.0.2.1")
          , Spec.iptables "filter" (Spec.IptablesState.HasRule "-P INPUT ACCEPT")
          , Spec.ip6tables "filter" (Spec.Ip6tablesState.HasRule "-P INPUT DROP")
          , Spec.ipfilter "block" (Spec.IpfilterState.HasRule "block in all")
          , Spec.ipnat "rdr" (Spec.IpnatState.HasRule "rdr en0 0/0 port 80 -> 127.0.0.1 port 8080")
          , Spec.routingTable
              ( Spec.RoutingTableState.HasEntry
                  { destination = "192.168.100.0/24"
                  , gateway     = "192.168.100.1"
                  }
              )
          , Spec.selinux Spec.SelinuxState.Enforcing
          , Spec.selinuxModule "virt" Spec.SelinuxModuleState.Installed
          , Spec.selinuxModule "virt" Spec.SelinuxModuleState.Enabled
          , Spec.linuxAuditSystem Spec.LinuxAuditSystemState.Running
          , Spec.linuxAuditSystem Spec.LinuxAuditSystemState.Enabled
          , Spec.linuxKernelParameter "net.ipv4.ip_forward"
              (Spec.LinuxKernelParameterState.HasValue "1")
          , Spec.cgroup "group1"
              ( Spec.CgroupState.HasParameter
                  { name = "cpu.shares", value = "256" }
              )
          ]
      ]
