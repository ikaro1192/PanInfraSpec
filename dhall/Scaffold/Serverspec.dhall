-- dhall/Scaffold/Serverspec.dhall
-- Shipped Serverspec scaffold. Mirrors `defaultServerspecScaffold` in
-- src/PanInfraSpec/Scaffold.hs (a unit test enforces this lockstep). Use
-- this prelude as the starting point when forking your own scaffold:
--
--    let serverspec = https://.../dhall/Scaffold/Serverspec.dhall
--    in  serverspec
--          // { staticFiles =
--                 [ { path    = "Rakefile"
--                   , content = ./my-rakefile.template as Text
--                   }
--                 , { path    = "spec_helper.rb"
--                   , content = ./my-spec-helper.template as Text
--                   }
--                 ]
--             }
--
-- The Rakefile and spec_helper.rb bodies are stored as plain text files in
-- the sibling `Serverspec/` directory and pulled in via Dhall's `as Text`
-- import. This keeps editor syntax highlighting and diff review usable on
-- the templates themselves.

let S = ../Scaffold.dhall
let I = ../Inventory.dhall

in  S.make
      { name            = "serverspec"
      , staticFiles     =
          [ { path    = "Rakefile"
            , content = ./Serverspec/Rakefile.template as Text
            }
          , { path    = "spec_helper.rb"
            , content = ./Serverspec/spec_helper.rb.template as Text
            }
          ]
      , derivedFiles    = \(_ : List I.Node) -> [] : List S.OutputFile
      , builtinDerivers = [] : List S.BuiltinDeriver
      }
