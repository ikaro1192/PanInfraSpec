require 'spec_helper'

paninfraspec_total_ram_kb = Specinfra.backend.run_command('awk \'/MemTotal/ {print $2}\' /proc/meminfo').stdout.strip
paninfraspec_max_mem_mb = Specinfra.backend.run_command('echo 256').stdout.strip
paninfraspec_min_cert_days = Specinfra.backend.run_command('echo 30').stdout.strip

# src: test/Golden/plan.dhall:32:13 — Spec.bond "bond0" Spec.BondState.Exist
# src: test/Golden/plan.dhall:33:13 — Spec.bond "bond0" (Spec.BondState.HasInterface "eth0")
describe bond('bond0') do
  it { should exist }
  it { should have_interface 'eth0' }
end

# src: test/Golden/plan.dhall:34:13 — Spec.bridge "br0" Spec.BridgeState.Exist
# src: test/Golden/plan.dhall:35:13 — Spec.bridge "br0" (Spec.BridgeState.HasInterface "eth1")
describe bridge('br0') do
  it { should exist }
  it { should have_interface 'eth1' }
end

# src: test/Golden/plan.dhall:58:13 — Spec.cgroup "group1" ( Spec.CgroupState.HasParameter { name = "cpu.shares", val…
describe cgroup('group1') do
  its('cpu.shares') { should eq '256' }
end

# src: test/Golden/plan.dhall:7:13 — Spec.command "uname -a" (Spec.CommandState.ExitCode 0)
describe command('uname -a') do
  its(:exit_status) { should eq 0 }
end

# src: test/Golden/plan.dhall:78:13 — Spec.cron ( Spec.CronState.HasEntryAsUser { entry = "0 4 * * * /usr/sbin/run_da…
describe cron do
  it { should have_entry('0 4 * * * /usr/sbin/run_daily_jobs').with_user('root') }
end

# src: test/Golden/plan.dhall:36:13 — Spec.defaultGateway (Spec.DefaultGatewayState.HasIpaddress "10.0.1.1")
# src: test/Golden/plan.dhall:37:13 — Spec.defaultGateway (Spec.DefaultGatewayState.HasInterface "eth0")
describe default_gateway do
  its(:interface) { should eq 'eth0' }
  its(:ipaddress) { should eq '10.0.1.1' }
end

# src: test/Golden/plan.dhall:207:13 — Spec.dockerContainer "focused_curie" Spec.DockerContainerState.Exist
# src: test/Golden/plan.dhall:209:13 — Spec.dockerContainer "focused_curie" Spec.DockerContainerState.Running
# src: test/Golden/plan.dhall:211:13 — Spec.dockerContainer "focused_curie" ( Spec.DockerContainerState.HasVolume { co…
# src: test/Golden/plan.dhall:215:13 — Spec.dockerContainer "focused_curie" ( Spec.DockerContainerState.InspectEqText …
# src: test/Golden/plan.dhall:219:13 — Spec.dockerContainer "focused_curie" ( Spec.DockerContainerState.InspectEqText …
describe docker_container('focused_curie') do
  it { should exist }
  its(['HostConfig.NetworkMode']) { should eq 'bridge' }
  its(['Path']) { should eq '/bin/sh' }
  it { should be_running }
  it { should have_volume('/tmp', '/data') }
end

# src: test/Golden/plan.dhall:223:13 — Spec.dockerImage "busybox:latest" Spec.DockerImageState.Exist
# src: test/Golden/plan.dhall:224:13 — Spec.dockerImage "busybox:latest" ( Spec.DockerImageState.InspectEqText { keyPa…
# src: test/Golden/plan.dhall:228:13 — Spec.dockerImage "busybox:latest" ( Spec.DockerImageState.InspectInclude { keyP…
# src: test/Golden/plan.dhall:232:13 — Spec.dockerImage "busybox:latest" ( Spec.DockerImageState.InspectionNotInclude …
describe docker_image('busybox:latest') do
  it { should exist }
  its(['Architecture']) { should eq 'amd64' }
  its(['Config.Cmd']) { should include '/bin/sh' }
  its(:inspection) { should_not include 'Architecture' => 'i386' }
end

# src: test/Golden/plan.dhall:104:13 — Spec.file "/etc/hosts" Spec.FileState.BeFile
describe file('/etc/hosts') do
  it { should be_file }
end

# src: test/Golden/plan.dhall:125:13 — Spec.file "/etc/localtime" (Spec.FileState.LinkedTo "/usr/share/zoneinfo/UTC")
describe file('/etc/localtime') do
  it { should be_linked_to '/usr/share/zoneinfo/UTC' }
end

# src: test/Golden/plan.dhall:105:13 — Spec.file "/etc/nginx" Spec.FileState.BeDirectory
describe file('/etc/nginx') do
  it { should be_directory }
end

# src: test/Golden/plan.dhall:12:13 — Spec.file "/etc/nginx/nginx.conf" Spec.FileState.Exist
describe file('/etc/nginx/nginx.conf') do
  it { should exist }
end

# src: test/Golden/plan.dhall:107:13 — Spec.file "/etc/passwd" Spec.FileState.BeImmutable -- Phase 2 follow-up: file p…
# src: test/Golden/plan.dhall:109:13 — Spec.file "/etc/passwd" Spec.FileState.Readable
describe file('/etc/passwd') do
  it { should be_readable }
  it { should be_immutable }
end

# src: test/Golden/plan.dhall:15:13 — Spec.file "/etc/profile" (Spec.FileState.Contains "PATH")
describe file('/etc/profile') do
  it { should contain 'PATH' }
end

# src: test/Golden/plan.dhall:116:13 — Spec.file "/etc/resolv.conf" ( Spec.FileState.ContainsFromTo { pattern = "names…
describe file('/etc/resolv.conf') do
  it { should contain('nameserver').from('# DNS').to('# end') }
end

# src: test/Golden/plan.dhall:110:13 — Spec.file "/etc/shadow" (Spec.FileState.ReadableByUser "root")
describe file('/etc/shadow') do
  it { should be_readable.by_user('root') }
end

# src: test/Golden/plan.dhall:113:13 — Spec.file "/etc/sudoers" (Spec.FileState.WritableByScope Spec.PermissionScope.O…
describe file('/etc/sudoers') do
  it { should be_writable.by(:owned) }
end

# src: test/Golden/plan.dhall:127:13 — Spec.file "/proc" ( Spec.FileState.MountedWith [ { mapKey = "type", mapValue = …
describe file('/proc') do
  it { should be_mounted.with(:type => 'proc') }
end

# src: test/Golden/plan.dhall:111:13 — Spec.file "/usr/local/bin/foo" (Spec.FileState.ExecutableByScope Spec.Permissio…
describe file('/usr/local/bin/foo') do
  it { should be_executable.by(:others) }
end

# src: test/Golden/plan.dhall:13:13 — Spec.file "/var/log/nginx" (Spec.FileState.OwnedBy "nginx")
# src: test/Golden/plan.dhall:14:13 — Spec.file "/var/log/nginx" (Spec.FileState.Mode 644)
describe file('/var/log/nginx') do
  it { should be_mode 644 }
  it { should be_owned_by 'nginx' }
end

# src: test/Golden/plan.dhall:120:13 — Spec.file "/var/log/syslog" ( Spec.FileState.ContainsAfter { pattern = "ERROR",…
describe file('/var/log/syslog') do
  it { should contain('ERROR').after('2026-01-01') }
end

# src: test/Golden/plan.dhall:106:13 — Spec.file "/var/run/docker.sock" Spec.FileState.BeSocket
describe file('/var/run/docker.sock') do
  it { should be_socket }
end

# src: test/Golden/plan.dhall:21:13 — Spec.group "nginx" Spec.GroupState.Exist
# src: test/Golden/plan.dhall:22:13 — Spec.group "nginx" (Spec.GroupState.HasGid 101)
describe group('nginx') do
  it { should exist }
  it { should have_gid 101 }
end

# src: test/Golden/plan.dhall:38:13 — Spec.host "example.jp" Spec.HostState.Resolvable
# src: test/Golden/plan.dhall:39:13 — Spec.host "example.jp" Spec.HostState.Reachable
# src: test/Golden/plan.dhall:40:13 — Spec.host "example.jp" (Spec.HostState.HasIpaddress "192.0.2.1")
# src: test/Golden/plan.dhall:65:13 — Spec.host "example.jp" ( Spec.HostState.ReachableWith { port = 22, proto = "tcp…
describe host('example.jp') do
  it { should be_reachable.with(:port => 22, :proto => 'tcp', :timeout => 1) }
  its(:ipaddress) { should eq '192.0.2.1' }
  it { should be_resolvable }
end

# src: test/Golden/plan.dhall:151:13 — Spec.iisAppPool "Default App Pool" Spec.IisAppPoolState.Exist
# src: test/Golden/plan.dhall:152:13 — Spec.iisAppPool "Default App Pool" (Spec.IisAppPoolState.HasDotnetVersion "2.0")
describe iis_app_pool('Default App Pool') do
  it { should have_dotnet_version('2.0') }
  it { should exist }
end

# src: test/Golden/plan.dhall:154:13 — Spec.iisWebsite "Default Website" Spec.IisWebsiteState.Exist
# src: test/Golden/plan.dhall:155:13 — Spec.iisWebsite "Default Website" Spec.IisWebsiteState.Enabled
# src: test/Golden/plan.dhall:156:13 — Spec.iisWebsite "Default Website" Spec.IisWebsiteState.Running
# src: test/Golden/plan.dhall:157:13 — Spec.iisWebsite "Default Website" (Spec.IisWebsiteState.InAppPool "Default App …
# src: test/Golden/plan.dhall:159:13 — Spec.iisWebsite "Default Website" (Spec.IisWebsiteState.HasPhysicalPath "C:\\in…
describe iis_website('Default Website') do
  it { should be_enabled }
  it { should exist }
  it { should be_in_app_pool('Default App Pool') }
  it { should have_physical_path('C:\\inetpub\\www') }
  it { should be_running }
end

# src: test/Golden/plan.dhall:28:13 — Spec.interface "eth0" Spec.InterfaceState.Exist
# src: test/Golden/plan.dhall:29:13 — Spec.interface "eth0" (Spec.InterfaceState.HasSpeed 1000)
# src: test/Golden/plan.dhall:30:13 — Spec.interface "eth0" (Spec.InterfaceState.HasIpv4Address "10.0.1.10")
# src: test/Golden/plan.dhall:136:13 — Spec.interface "eth0" Spec.InterfaceState.Up
# src: test/Golden/plan.dhall:137:13 — Spec.interface "eth0" (Spec.InterfaceState.HasIpv6Address "fe80::1") -- Phase 2…
describe interface('eth0') do
  it { should exist }
  it { should have_ipv4_address '10.0.1.10' }
  it { should have_ipv6_address 'fe80::1' }
  its(:speed) { should eq 1000 }
  it { should be_up }
end

# src: test/Golden/plan.dhall:42:13 — Spec.ip6tables "filter" (Spec.Ip6tablesState.HasRule "-P INPUT DROP")
describe ip6tables('filter') do
  it { should have_rule '-P INPUT DROP' }
end

# src: test/Golden/plan.dhall:43:13 — Spec.ipfilter "block" (Spec.IpfilterState.HasRule "block in all")
describe ipfilter('block') do
  it { should have_rule 'block in all' }
end

# src: test/Golden/plan.dhall:44:13 — Spec.ipnat "rdr" (Spec.IpnatState.HasRule "rdr en0 0/0 port 80 -> 127.0.0.1 por…
describe ipnat('rdr') do
  it { should have_rule 'rdr en0 0/0 port 80 -> 127.0.0.1 port 8080' }
end

# src: test/Golden/plan.dhall:41:13 — Spec.iptables "filter" (Spec.IptablesState.HasRule "-P INPUT ACCEPT")
describe iptables('filter') do
  it { should have_rule '-P INPUT ACCEPT' }
end

# src: test/Golden/plan.dhall:31:13 — Spec.kernelModule "br_netfilter" Spec.KernelModuleState.Loaded
describe kernel_module('br_netfilter') do
  it { should be_loaded }
end

# src: test/Golden/plan.dhall:54:13 — Spec.linuxAuditSystem Spec.LinuxAuditSystemState.Running
# src: test/Golden/plan.dhall:55:13 — Spec.linuxAuditSystem Spec.LinuxAuditSystemState.Enabled
describe linux_audit_system do
  it { should be_enabled }
  it { should be_running }
end

# src: test/Golden/plan.dhall:56:13 — Spec.linuxKernelParameter "net.ipv4.ip_forward" (Spec.LinuxKernelParameterState…
describe linux_kernel_parameter('net.ipv4.ip_forward') do
  its(:value) { should eq '1' }
end

# src: test/Golden/plan.dhall:144:13 — Spec.lxc "ct01" Spec.LxcState.Exist
# src: test/Golden/plan.dhall:145:13 — Spec.lxc "ct01" Spec.LxcState.Running
describe lxc('ct01') do
  it { should exist }
  it { should be_running }
end

# src: test/Golden/plan.dhall:146:13 — Spec.mailAlias "daemon" (Spec.MailAliasState.AliasedTo "root")
describe mail_alias('daemon') do
  it { should be_aliased_to 'root' }
end

# src: test/Golden/plan.dhall:25:13 — Spec.mount "/data" Spec.MountState.Mounted
# src: test/Golden/plan.dhall:26:13 — Spec.mount "/data" (Spec.MountState.OnDevice "/dev/sda1")
# src: test/Golden/plan.dhall:27:13 — Spec.mount "/data" (Spec.MountState.OfFstype "ext4")
describe mount('/data') do
  its(:device) { should eq '/dev/sda1' }
  its(:fstype) { should eq 'ext4' }
  it { should be_mounted }
end

# src: test/Golden/plan.dhall:161:13 — Spec.mysqlConfig "innodb-buffer-pool-size" ( Spec.MysqlConfigState.Compare { op…
describe mysql_config('innodb-buffer-pool-size') do
  its(:value) { should be > 100000000 }
end

# src: test/Golden/plan.dhall:167:13 — Spec.mysqlConfig "innodb_buffer_pool_size_bytes" ( Spec.MysqlConfigState.Compar…
describe mysql_config('innodb_buffer_pool_size_bytes') do
  its(:value) { should be > paninfraspec_total_ram_kb.to_i * 1024 * 70 / 100 }
end

# src: test/Golden/plan.dhall:175:13 — Spec.mysqlConfig "socket" (Spec.MysqlConfigState.EqText "/tmp/mysql.sock")
describe mysql_config('socket') do
  its(:value) { should eq '/tmp/mysql.sock' }
end

# src: test/Golden/plan.dhall:8:13 — Spec.package "nginx" Spec.PackageState.Installed
describe package('nginx') do
  it { should be_installed }
end

# src: test/Golden/plan.dhall:177:13 — Spec.phpConfig "default_mimetype" (Spec.PhpConfigState.EqText "text/html") -- C…
describe php_config('default_mimetype') do
  its(:value) { should eq 'text/html' }
end

# src: test/Golden/plan.dhall:190:13 — Spec.phpConfigWithIni "display_errors" "/etc/php/7.1/fpm/php.ini" (Spec.PhpConf…
describe php_config('display_errors', :ini => '/etc/php/7.1/fpm/php.ini') do
  its(:value) { should eq 1 }
end

# src: test/Golden/plan.dhall:188:13 — Spec.phpConfig "mbstring.http_output_conv_mimetypes" (Spec.PhpConfigState.Match…
describe php_config('mbstring.http_output_conv_mimetypes') do
  its(:value) { should match /application/ }
end

# src: test/Golden/plan.dhall:180:13 — Spec.phpConfig "memory_limit_mb" ( Spec.PhpConfigState.CompareExpr { op = Spec.…
describe php_config('memory_limit_mb') do
  its(:value) { should be <= paninfraspec_max_mem_mb.to_i }
end

# src: test/Golden/plan.dhall:186:13 — Spec.phpConfig "session.cache_expire" (Spec.PhpConfigState.EqNat 180)
describe php_config('session.cache_expire') do
  its(:value) { should eq 180 }
end

# src: test/Golden/plan.dhall:11:13 — Spec.port 80 (Spec.PortState.WithProtocol "tcp")
describe port(80) do
  it { should be_listening.with('tcp') }
end

# src: test/Golden/plan.dhall:147:13 — Spec.ppa "launchpad-username/ppa-name" Spec.PpaState.Exist
# src: test/Golden/plan.dhall:148:13 — Spec.ppa "launchpad-username/ppa-name" Spec.PpaState.Enabled
describe ppa('launchpad-username/ppa-name') do
  it { should be_enabled }
  it { should exist }
end

# src: test/Golden/plan.dhall:23:13 — Spec.process "nginx" Spec.ProcessState.Running
# src: test/Golden/plan.dhall:24:13 — Spec.process "nginx" (Spec.ProcessState.RunByUser "nginx")
# src: test/Golden/plan.dhall:139:13 — Spec.process "nginx" (Spec.ProcessState.HasGroup "nginx")
# src: test/Golden/plan.dhall:140:13 — Spec.process "nginx" (Spec.ProcessState.HasArgs "-c /etc/nginx/nginx.conf")
# src: test/Golden/plan.dhall:142:13 — Spec.process "nginx" (Spec.ProcessState.HasCount 4) -- Phase 3: serverspec.org …
describe process('nginx') do
  its(:args) { should eq '-c /etc/nginx/nginx.conf' }
  its(:count) { should eq 4 }
  its(:group) { should eq 'nginx' }
  it { should be_running }
  its(:user) { should eq 'nginx' }
end

# src: test/Golden/plan.dhall:45:13 — Spec.routingTable ( Spec.RoutingTableState.HasEntry { destination = "192.168.10…
# src: test/Golden/plan.dhall:69:13 — Spec.routingTable ( Spec.RoutingTableState.HasEntryFull { destination = "192.16…
describe routing_table do
  it { should have_entry :destination => '192.168.100.0/24', :gateway => '192.168.100.1' }
  it { should have_entry :destination => '192.168.200.0/24', :gateway => '192.168.200.1', :interface => 'eth1' }
end

# src: test/Golden/plan.dhall:51:13 — Spec.selinux Spec.SelinuxState.Enforcing
describe selinux do
  it { should be_enforcing }
end

# src: test/Golden/plan.dhall:52:13 — Spec.selinuxModule "virt" Spec.SelinuxModuleState.Installed
# src: test/Golden/plan.dhall:53:13 — Spec.selinuxModule "virt" Spec.SelinuxModuleState.Enabled
# src: test/Golden/plan.dhall:63:13 — Spec.selinuxModule "virt" (Spec.SelinuxModuleState.WithVersion "1.5.0")
describe selinux_module('virt') do
  it { should be_installed.with_version('1.5.0') }
  it { should be_enabled }
end

# src: test/Golden/plan.dhall:9:13 — Spec.service "nginx" Spec.ServiceState.Running
# src: test/Golden/plan.dhall:10:13 — Spec.service "nginx" Spec.ServiceState.Enabled
describe service('nginx') do
  it { should be_enabled }
  it { should be_running }
end

# src: test/Golden/plan.dhall:133:13 — Spec.user "deploy" (Spec.UserState.HasAuthorizedKey "ssh-rsa AAAA...") -- Phase…
describe user('deploy') do
  it { should have_authorized_key 'ssh-rsa AAAA...' }
end

# src: test/Golden/plan.dhall:16:13 — Spec.user "nginx" Spec.UserState.Exist
# src: test/Golden/plan.dhall:17:13 — Spec.user "nginx" (Spec.UserState.HasUid 101)
# src: test/Golden/plan.dhall:18:13 — Spec.user "nginx" (Spec.UserState.BelongsToGroup "nginx")
# src: test/Golden/plan.dhall:19:13 — Spec.user "nginx" (Spec.UserState.HasHomeDirectory "/var/lib/nginx")
# src: test/Golden/plan.dhall:20:13 — Spec.user "nginx" (Spec.UserState.HasLoginShell "/usr/sbin/nologin")
# src: test/Golden/plan.dhall:132:13 — Spec.user "nginx" (Spec.UserState.BelongsToPrimaryGroup "nginx")
describe user('nginx') do
  it { should belong_to_group 'nginx' }
  it { should belong_to_primary_group 'nginx' }
  it { should exist }
  it { should have_home_directory '/var/lib/nginx' }
  it { should have_login_shell '/usr/sbin/nologin' }
  it { should have_uid 101 }
end

# src: test/Golden/plan.dhall:76:13 — Spec.windowsFeature "Minesweeper" (Spec.WindowsFeatureState.InstalledBy "dism")
describe windows_feature('Minesweeper') do
  it { should be_installed.by('dism') }
end

# src: test/Golden/plan.dhall:95:13 — Spec.windowsRegistryKey "HKEY_LOCAL_MACHINE\\Some\\Key" ( Spec.WindowsRegistryK…
# src: test/Golden/plan.dhall:99:13 — Spec.windowsRegistryKey "HKEY_LOCAL_MACHINE\\Some\\Key" ( Spec.WindowsRegistryK…
describe windows_registry_key('HKEY_LOCAL_MACHINE\\Some\\Key') do
  it { should have_property 'NumProperty', :type_dword }
  it { should have_property_value 'NumProperty', :type_dword, 1 }
end

# src: test/Golden/plan.dhall:84:13 — Spec.x509Certificate "/etc/ssl/cert.pem" ( Spec.X509CertificateState.ValidityIn…
describe x509_certificate('/etc/ssl/cert.pem') do
  its(:validity_in_days) { should be > 30 }
end

# src: test/Golden/plan.dhall:89:13 — Spec.x509Certificate "/etc/ssl/server.crt" ( Spec.X509CertificateState.Validity…
describe x509_certificate('/etc/ssl/server.crt') do
  its(:validity_in_days) { should be >= paninfraspec_min_cert_days.to_i }
end

# src: test/Golden/plan.dhall:192:13 — Spec.x509PrivateKey "/my/private/server-key.pem" Spec.X509PrivateKeyState.NotEn…
# src: test/Golden/plan.dhall:194:13 — Spec.x509PrivateKey "/my/private/server-key.pem" Spec.X509PrivateKeyState.Valid
# src: test/Golden/plan.dhall:196:13 — Spec.x509PrivateKey "/my/private/server-key.pem" ( Spec.X509PrivateKeyState.Has…
describe x509_private_key('/my/private/server-key.pem') do
  it { should have_matching_certificate('/my/certs/server-cert.pem') }
  it { should_not be_encrypted }
  it { should be_valid }
end

# src: test/Golden/plan.dhall:149:13 — Spec.yumrepo "epel" Spec.YumrepoState.Exist
# src: test/Golden/plan.dhall:150:13 — Spec.yumrepo "epel" Spec.YumrepoState.Enabled
describe yumrepo('epel') do
  it { should be_enabled }
  it { should exist }
end

# src: test/Golden/plan.dhall:200:13 — Spec.zfs "rpool" Spec.ZfsState.Exist
# src: test/Golden/plan.dhall:201:13 — Spec.zfs "rpool" ( Spec.ZfsState.HasProperty [ { mapKey = "compression", mapVal…
describe zfs('rpool') do
  it { should exist }
  it { should have_property 'compression' => 'off', 'mountpoint' => '/rpool' }
end
