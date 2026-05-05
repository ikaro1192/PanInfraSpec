require 'spec_helper'

# src: test/Golden/ansible_spec/plan.dhall:8:17 — Spec.package "nginx" Spec.PackageState.Installed
describe package('nginx') do
  it { should be_installed }
end

# src: test/Golden/ansible_spec/plan.dhall:10:17 — Spec.port 80 Spec.PortState.Listening
describe port(80) do
  it { should be_listening }
end

# src: test/Golden/ansible_spec/plan.dhall:9:17 — Spec.service "nginx" Spec.ServiceState.Running
describe service('nginx') do
  it { should be_running }
end
