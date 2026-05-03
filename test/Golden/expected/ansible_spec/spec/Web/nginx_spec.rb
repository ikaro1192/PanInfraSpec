require 'spec_helper'

describe package('nginx') do
  it { should be_installed }
end

describe port(80) do
  it { should be_listening }
end

describe service('nginx') do
  it { should be_running }
end
