require 'spec_helper'

describe command('uname -a') do
  its(:exit_status) { should eq 0 }
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

describe interface('eth0') do
  it { should exist }
  it { should have_ipv4_address '10.0.1.10' }
  its(:speed) { should eq 1000 }
end

describe kernel_module('br_netfilter') do
  it { should be_loaded }
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
  it { should be_listening.with('tcp') }
end

describe process('nginx') do
  it { should be_running }
  its(:user) { should eq 'nginx' }
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
