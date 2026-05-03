require 'spec_helper'

describe package('mysql-server') do
  it { should be_installed }
end

describe port(3306) do
  it { should be_listening }
end

describe service('mysqld') do
  it { should be_running }
end
