require 'spec_helper'

# src: test/Golden/ansible_spec/plan.dhall:15:17 — Spec.package "php-fpm" Spec.PackageState.Installed
describe package('php-fpm') do
  it { should be_installed }
end

# src: test/Golden/ansible_spec/plan.dhall:16:17 — Spec.service "php-fpm" Spec.ServiceState.Running
describe service('php-fpm') do
  it { should be_running }
end
