require 'spec_helper'

describe command('uname -a') do
  its(:exit_status) { should eq 0 }
end

describe port(5432) do
  it { should be_listening }
end
