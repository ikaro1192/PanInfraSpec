-- examples/scaffold-custom.dhall
-- Demonstrate forking the shipped Serverspec scaffold: drop in a
-- Bundler-flavoured Rakefile while keeping the rest of the defaults.
--
-- Run with:
--   cabal run paninfraspec-gen -- \
--     --inventory examples/inventory.dhall \
--     --plan      examples/plan.dhall \
--     --target    serverspec \
--     --scaffold  examples/scaffold-custom.dhall \
--     --out       /tmp/custom-out

let serverspec = ../dhall/Scaffold/Serverspec.dhall

let customRakefile =
      ''
      # Custom Rakefile that defers to bundler so spec deps stay isolated.
      require 'rake'
      require 'rspec/core/rake_task'

      RSpec::Core::RakeTask.new(:spec) do |t|
        t.pattern    = '*_spec.rb'
        t.rspec_opts = '--format documentation'
      end

      task default: :spec
      ''

in  serverspec
      // { staticFiles =
            [ { path = "Rakefile",       content = customRakefile }
            , { path    = "spec_helper.rb"
              , content =
                  ../dhall/Scaffold/Serverspec/spec_helper.rb.template as Text
              }
            ]
        }
