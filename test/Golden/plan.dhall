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
          -- Issue #3 follow-up matchers
          , Spec.selinuxModule "virt"
              (Spec.SelinuxModuleState.WithVersion "1.5.0")
          , Spec.host "example.jp"
              ( Spec.HostState.ReachableWith
                  { port = 22, proto = "tcp", timeout = 1 }
              )
          , Spec.routingTable
              ( Spec.RoutingTableState.HasEntryFull
                  { destination = "192.168.200.0/24"
                  , gateway     = "192.168.200.1"
                  , interface   = "eth1"
                  }
              )
          , Spec.windowsFeature "Minesweeper"
              (Spec.WindowsFeatureState.InstalledBy "dism")
          , Spec.cron
              ( Spec.CronState.HasEntryAsUser
                  { entry = "0 4 * * * /usr/sbin/run_daily_jobs"
                  , user  = "root"
                  }
              )
          , Spec.x509Certificate "/etc/ssl/cert.pem"
              ( Spec.X509CertificateState.ValidityInDaysCompare
                  { op = Spec.CompareOp.Gt, value = 30 }
              )
          , Spec.windowsRegistryKey "HKEY_LOCAL_MACHINE\\Some\\Key"
              ( Spec.WindowsRegistryKeyState.HasProperty
                  { name = "NumProperty", propertyType = "type_dword" }
              )
          , Spec.windowsRegistryKey "HKEY_LOCAL_MACHINE\\Some\\Key"
              ( Spec.WindowsRegistryKeyState.HasPropertyValue
                  { name = "NumProperty", propertyType = "type_dword", value = 1 }
              )
          -- Phase 2 follow-up: file simple type matchers
          , Spec.file "/etc/hosts"           Spec.FileState.BeFile
          , Spec.file "/etc/nginx"           Spec.FileState.BeDirectory
          , Spec.file "/var/run/docker.sock" Spec.FileState.BeSocket
          , Spec.file "/etc/passwd"          Spec.FileState.BeImmutable
          -- Phase 2 follow-up: file permission chain matchers
          , Spec.file "/etc/passwd" Spec.FileState.Readable
          , Spec.file "/etc/shadow" (Spec.FileState.ReadableByUser "root")
          , Spec.file "/usr/local/bin/foo"
              (Spec.FileState.ExecutableByScope Spec.PermissionScope.Others)
          , Spec.file "/etc/sudoers"
              (Spec.FileState.WritableByScope Spec.PermissionScope.Owner)
          -- Phase 2 follow-up: file contain chain matchers
          , Spec.file "/etc/resolv.conf"
              ( Spec.FileState.ContainsFromTo
                  { pattern = "nameserver", from = "# DNS", to = "# end" }
              )
          , Spec.file "/var/log/syslog"
              ( Spec.FileState.ContainsAfter
                  { pattern = "ERROR", after = "2026-01-01" }
              )
          -- Phase 2 follow-up: file link / mounted matchers
          , Spec.file "/etc/localtime"
              (Spec.FileState.LinkedTo "/usr/share/zoneinfo/UTC")
          , Spec.file "/proc"
              ( Spec.FileState.MountedWith
                  [ { mapKey = "type", mapValue = "proc" } ]
              )
          -- Phase 2 follow-up: user
          , Spec.user "nginx" (Spec.UserState.BelongsToPrimaryGroup "nginx")
          , Spec.user "deploy"
              (Spec.UserState.HasAuthorizedKey "ssh-rsa AAAA...")
          -- Phase 2 follow-up: interface
          , Spec.interface "eth0" Spec.InterfaceState.Up
          , Spec.interface "eth0" (Spec.InterfaceState.HasIpv6Address "fe80::1")
          -- Phase 2 follow-up: process
          , Spec.process "nginx" (Spec.ProcessState.HasGroup "nginx")
          , Spec.process "nginx"
              (Spec.ProcessState.HasArgs "-c /etc/nginx/nginx.conf")
          , Spec.process "nginx" (Spec.ProcessState.HasCount 4)
          ]
      ]
