require 'spec_helper'

describe bond('bond0') do
  it { should exist }
  it { should have_interface 'eth0' }
end

describe bridge('br0') do
  it { should exist }
  it { should have_interface 'eth1' }
end

describe cgroup('group1') do
  its('cpu.shares') { should eq '256' }
end

describe command('uname -a') do
  its(:exit_status) { should eq 0 }
end

describe cron do
  it { should have_entry('0 4 * * * /usr/sbin/run_daily_jobs').with_user('root') }
end

describe default_gateway do
  its(:interface) { should eq 'eth0' }
  its(:ipaddress) { should eq '10.0.1.1' }
end

describe docker_container('focused_curie') do
  it { should exist }
  its(['HostConfig.NetworkMode']) { should eq 'bridge' }
  its(['Path']) { should eq '/bin/sh' }
  it { should be_running }
  it { should have_volume('/tmp', '/data') }
end

describe docker_image('busybox:latest') do
  it { should exist }
  its(['Architecture']) { should eq 'amd64' }
  its(['Config.Cmd']) { should include '/bin/sh' }
  its(:inspection) { should_not include 'Architecture' => 'i386' }
end

describe file('/etc/hosts') do
  it { should be_file }
end

describe file('/etc/localtime') do
  it { should be_linked_to '/usr/share/zoneinfo/UTC' }
end

describe file('/etc/nginx') do
  it { should be_directory }
end

describe file('/etc/nginx/nginx.conf') do
  it { should exist }
end

describe file('/etc/passwd') do
  it { should be_readable }
  it { should be_immutable }
end

describe file('/etc/profile') do
  it { should contain 'PATH' }
end

describe file('/etc/resolv.conf') do
  it { should contain('nameserver').from('# DNS').to('# end') }
end

describe file('/etc/shadow') do
  it { should be_readable.by_user('root') }
end

describe file('/etc/sudoers') do
  it { should be_writable.by(:owned) }
end

describe file('/proc') do
  it { should be_mounted.with(:type => 'proc') }
end

describe file('/usr/local/bin/foo') do
  it { should be_executable.by(:others) }
end

describe file('/var/log/nginx') do
  it { should be_mode 644 }
  it { should be_owned_by 'nginx' }
end

describe file('/var/log/syslog') do
  it { should contain('ERROR').after('2026-01-01') }
end

describe file('/var/run/docker.sock') do
  it { should be_socket }
end

describe group('nginx') do
  it { should exist }
  it { should have_gid 101 }
end

describe host('example.jp') do
  it { should be_reachable.with(:port => 22, :proto => 'tcp', :timeout => 1) }
  its(:ipaddress) { should eq '192.0.2.1' }
  it { should be_resolvable }
end

describe iis_app_pool('Default App Pool') do
  it { should have_dotnet_version('2.0') }
  it { should exist }
end

describe iis_website('Default Website') do
  it { should be_enabled }
  it { should exist }
  it { should be_in_app_pool('Default App Pool') }
  it { should have_physical_path('C:\\inetpub\\www') }
  it { should be_running }
end

describe interface('eth0') do
  it { should exist }
  it { should have_ipv4_address '10.0.1.10' }
  it { should have_ipv6_address 'fe80::1' }
  its(:speed) { should eq 1000 }
  it { should be_up }
end

describe ip6tables('filter') do
  it { should have_rule '-P INPUT DROP' }
end

describe ipfilter('block') do
  it { should have_rule 'block in all' }
end

describe ipnat('rdr') do
  it { should have_rule 'rdr en0 0/0 port 80 -> 127.0.0.1 port 8080' }
end

describe iptables('filter') do
  it { should have_rule '-P INPUT ACCEPT' }
end

describe kernel_module('br_netfilter') do
  it { should be_loaded }
end

describe linux_audit_system do
  it { should be_enabled }
  it { should be_running }
end

describe linux_kernel_parameter('net.ipv4.ip_forward') do
  its(:value) { should eq '1' }
end

describe lxc('ct01') do
  it { should exist }
  it { should be_running }
end

describe mail_alias('daemon') do
  it { should be_aliased_to 'root' }
end

describe mount('/data') do
  its(:device) { should eq '/dev/sda1' }
  its(:fstype) { should eq 'ext4' }
  it { should be_mounted }
end

describe mysql_config('innodb-buffer-pool-size') do
  its(:value) { should be > 100000000 }
end

describe mysql_config('socket') do
  its(:value) { should eq '/tmp/mysql.sock' }
end

describe package('nginx') do
  it { should be_installed }
end

describe php_config('default_mimetype') do
  its(:value) { should eq 'text/html' }
end

describe php_config('display_errors', :ini => '/etc/php/7.1/fpm/php.ini') do
  its(:value) { should eq 1 }
end

describe php_config('mbstring.http_output_conv_mimetypes') do
  its(:value) { should match /application/ }
end

describe php_config('session.cache_expire') do
  its(:value) { should eq 180 }
end

describe port(80) do
  it { should be_listening.with('tcp') }
end

describe ppa('launchpad-username/ppa-name') do
  it { should be_enabled }
  it { should exist }
end

describe process('nginx') do
  its(:args) { should eq '-c /etc/nginx/nginx.conf' }
  its(:count) { should eq 4 }
  its(:group) { should eq 'nginx' }
  it { should be_running }
  its(:user) { should eq 'nginx' }
end

describe routing_table do
  it { should have_entry :destination => '192.168.100.0/24', :gateway => '192.168.100.1' }
  it { should have_entry :destination => '192.168.200.0/24', :gateway => '192.168.200.1', :interface => 'eth1' }
end

describe selinux do
  it { should be_enforcing }
end

describe selinux_module('virt') do
  it { should be_installed.with_version('1.5.0') }
  it { should be_enabled }
end

describe service('nginx') do
  it { should be_enabled }
  it { should be_running }
end

describe user('deploy') do
  it { should have_authorized_key 'ssh-rsa AAAA...' }
end

describe user('nginx') do
  it { should belong_to_group 'nginx' }
  it { should belong_to_primary_group 'nginx' }
  it { should exist }
  it { should have_home_directory '/var/lib/nginx' }
  it { should have_login_shell '/usr/sbin/nologin' }
  it { should have_uid 101 }
end

describe windows_feature('Minesweeper') do
  it { should be_installed.by('dism') }
end

describe windows_registry_key('HKEY_LOCAL_MACHINE\\Some\\Key') do
  it { should have_property 'NumProperty', :type_dword }
  it { should have_property_value 'NumProperty', :type_dword, 1 }
end

describe x509_certificate('/etc/ssl/cert.pem') do
  its(:validity_in_days) { should be > 30 }
end

describe x509_private_key('/my/private/server-key.pem') do
  it { should have_matching_certificate('/my/certs/server-cert.pem') }
  it { should_not be_encrypted }
  it { should be_valid }
end

describe yumrepo('epel') do
  it { should be_enabled }
  it { should exist }
end

describe zfs('rpool') do
  it { should exist }
  it { should have_property 'compression' => 'off', 'mountpoint' => '/rpool' }
end
