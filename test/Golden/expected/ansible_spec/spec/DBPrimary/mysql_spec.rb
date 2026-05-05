require 'spec_helper'

# src: test/Golden/ansible_spec/plan.dhall:21:17 — Spec.package "mysql-server" Spec.PackageState.Installed
describe package('mysql-server') do
  it { should be_installed }
end

# src: test/Golden/ansible_spec/plan.dhall:23:17 — Spec.port 3306 Spec.PortState.Listening
describe port(3306) do
  it { should be_listening }
end

# src: test/Golden/ansible_spec/plan.dhall:22:17 — Spec.service "mysqld" Spec.ServiceState.Running
describe service('mysqld') do
  it { should be_running }
end
