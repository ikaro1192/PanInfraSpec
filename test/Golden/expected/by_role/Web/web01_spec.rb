require 'spec_helper'

# src: test/Golden/by_role/plan.dhall:7:13 — Spec.command "uname -a" (Spec.CommandState.ExitCode 0)
describe command('uname -a') do
  its(:exit_status) { should eq 0 }
end

# src: test/Golden/by_role/plan.dhall:9:13 — Spec.port 80 Spec.PortState.Listening
describe port(80) do
  it { should be_listening }
end
