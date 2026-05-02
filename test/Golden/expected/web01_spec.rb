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

describe default_gateway do
  its(:interface) { should eq 'eth0' }
  its(:ipaddress) { should eq '10.0.1.1' }
end

describe file('/etc/nginx/nginx.conf') do
  it { should exist }
end

describe file('/etc/profile') do
  it { should contain 'PATH' }
end

describe file('/var/log/nginx') do
  it { should be_mode 644 }
  it { should be_owned_by 'nginx' }
end

describe group('nginx') do
  it { should exist }
  it { should have_gid 101 }
end

describe host('example.jp') do
  its(:ipaddress) { should eq '192.0.2.1' }
  it { should be_reachable }
  it { should be_resolvable }
end

describe interface('eth0') do
  it { should exist }
  it { should have_ipv4_address '10.0.1.10' }
  its(:speed) { should eq 1000 }
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

describe mount('/data') do
  its(:device) { should eq '/dev/sda1' }
  its(:fstype) { should eq 'ext4' }
  it { should be_mounted }
end

describe package('nginx') do
  it { should be_installed }
end

describe port(80) do
  it { should be_listening }
end

describe process('nginx') do
  it { should be_running }
  its(:user) { should eq 'nginx' }
end

describe routing_table do
  it { should have_entry :destination => '192.168.100.0/24', :gateway => '192.168.100.1' }
end

describe selinux do
  it { should be_enforcing }
end

describe selinux_module('virt') do
  it { should be_enabled }
  it { should be_installed }
end

describe service('nginx') do
  it { should be_enabled }
  it { should be_running }
end

describe user('nginx') do
  it { should belong_to_group 'nginx' }
  it { should exist }
  it { should have_home_directory '/var/lib/nginx' }
  it { should have_login_shell '/usr/sbin/nologin' }
  it { should have_uid 101 }
end
