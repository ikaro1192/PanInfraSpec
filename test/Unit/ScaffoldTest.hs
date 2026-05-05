module Unit.ScaffoldTest (tests) where

import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Scaffold
  ( Scaffold (..)
  , OutputFile (..)
  , loadScaffold
  , resolveBuiltinDerivers
  )
import PanInfraSpec.Scaffold.Defaults.Serverspec (defaultServerspecScaffold)
import PanInfraSpec.IR (Node (..), Role (..))

tests :: TestTree
tests = testGroup "Scaffold"
  [ testCase "default Serverspec scaffold has Rakefile and spec_helper.rb"
      defaultHasWellKnownFiles
  , testCase "default scaffold derivedFiles always returns empty"
      defaultDerivedEmpty
  , testCase "loadScaffold fails cleanly on missing path"
      loadScaffoldMissingPath
  , testCase "shipped Serverspec.dhall matches defaultServerspecScaffold"
      shippedMatchesDefault
  , testCase "examples/scaffold-custom.dhall loads and overrides Rakefile"
      customScaffoldLoads
  , testCase "shipped AnsibleSpec.dhall loads"
      ansibleSpecLoads
  , testCase "AnsibleSpec derivedFiles produces hosts INI and site.yml"
      ansibleSpecDerivedFiles
  ]

defaultHasWellKnownFiles :: IO ()
defaultHasWellKnownFiles =
  let paths = map ofPath (sStaticFiles defaultServerspecScaffold)
   in do
        assertBool "Rakefile present"       ("Rakefile"       `elem` paths)
        assertBool "spec_helper.rb present" ("spec_helper.rb" `elem` paths)

defaultDerivedEmpty :: IO ()
defaultDerivedEmpty =
  sDerivedFiles defaultServerspecScaffold [] @?= []

loadScaffoldMissingPath :: IO ()
loadScaffoldMissingPath = do
  res <- loadScaffold "/nonexistent/path/to/scaffold.dhall"
  case res of
    Left e | T.length e > 0 -> pure ()
    Left _                  -> assertFailure "expected non-empty error message"
    Right _                 -> assertFailure "expected Left for missing path"

-- | The shipped @dhall/Scaffold/Serverspec.dhall@ must produce a 'Scaffold'
-- whose visible behaviour exactly matches 'defaultServerspecScaffold'. This
-- is what guarantees a user who forks the shipped Dhall scaffold sees the
-- same starting point as the built-in default.
shippedMatchesDefault :: IO ()
shippedMatchesDefault = do
  res <- loadScaffold "dhall/Scaffold/Serverspec.dhall"
  case res of
    Left e  -> assertFailure ("loadScaffold failed: " <> T.unpack e)
    Right s -> do
      sName s         @?= sName defaultServerspecScaffold
      sStaticFiles s  @?= sStaticFiles defaultServerspecScaffold
      sDerivedFiles s [] @?= sDerivedFiles defaultServerspecScaffold []

-- | The example @examples/scaffold-custom.dhall@ should load and override
-- the Rakefile content while keeping spec_helper.rb sourced from the
-- shipped template.
customScaffoldLoads :: IO ()
customScaffoldLoads = do
  res <- loadScaffold "examples/scaffold-custom.dhall"
  case res of
    Left e  -> assertFailure ("loadScaffold failed: " <> T.unpack e)
    Right s -> do
      let staticByPath = [(ofPath o, ofContent o) | o <- sStaticFiles s]
      case lookup "Rakefile" staticByPath of
        Nothing -> assertFailure "Rakefile entry missing from custom scaffold"
        Just c  -> assertBool "custom Rakefile mentions Bundler comment"
                     ("bundler" `T.isInfixOf` c)
      case lookup "spec_helper.rb" staticByPath of
        Nothing -> assertFailure "spec_helper.rb entry missing"
        Just c  -> assertBool "spec_helper.rb still sources serverspec"
                     ("require 'serverspec'" `T.isInfixOf` c)

ansibleSpecLoads :: IO ()
ansibleSpecLoads = do
  res <- loadScaffold "dhall/Scaffold/AnsibleSpec.dhall"
  case res of
    Left e  -> assertFailure ("loadScaffold failed: " <> T.unpack e)
    Right s -> do
      sName s @?= "ansible_spec"
      let staticPaths = map ofPath (sStaticFiles s)
      assertBool "Rakefile present"
        ("Rakefile" `elem` staticPaths)
      assertBool "spec_helper.rb present"
        ("spec_helper.rb" `elem` staticPaths)
      let rake = head [ ofContent o | o <- sStaticFiles s, ofPath o == "Rakefile" ]
      assertBool "Rakefile uses ansible_spec"
        ("require 'ansible_spec'" `T.isInfixOf` rake)

ansibleSpecDerivedFiles :: IO ()
ansibleSpecDerivedFiles = do
  res <- loadScaffold "dhall/Scaffold/AnsibleSpec.dhall"
  case res of
    Left e  -> assertFailure ("loadScaffold failed: " <> T.unpack e)
    Right s -> do
      let nodes =
            [ Node "web01" Nothing (Role "Web") [] []
            , Node "web02" Nothing (Role "Web") [] []
            , Node "db01"  Nothing (Role "DBPrimary") [] []
            ]
          derived = resolveBuiltinDerivers nodes (sBuiltinDerivers s)
          paths   = map ofPath derived
      assertBool "hosts file produced"
        ("hosts" `elem` paths)
      assertBool "site.yml file produced"
        ("site.yml" `elem` paths)
      let hosts = head [ ofContent o | o <- derived, ofPath o == "hosts" ]
      assertBool "hosts contains [Web] section"
        ("[Web]" `T.isInfixOf` hosts)
      assertBool "hosts contains [DBPrimary] section"
        ("[DBPrimary]" `T.isInfixOf` hosts)
      assertBool "hosts contains web01"
        ("web01" `T.isInfixOf` hosts)
      assertBool "hosts contains web02"
        ("web02" `T.isInfixOf` hosts)
      assertBool "hosts contains db01"
        ("db01"  `T.isInfixOf` hosts)
      let site  = head [ ofContent o | o <- derived, ofPath o == "site.yml" ]
      assertBool "site.yml mentions hosts: Web"
        ("hosts: Web" `T.isInfixOf` site)
      assertBool "site.yml mentions hosts: DBPrimary"
        ("hosts: DBPrimary" `T.isInfixOf` site)
