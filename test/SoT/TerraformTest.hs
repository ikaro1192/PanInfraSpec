module SoT.TerraformTest (tests) where

import Data.Maybe (fromJust)
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.IR
import PanInfraSpec.SoT (toNodes)
import PanInfraSpec.SoT.Terraform
  ( TerraformStateFile (..)
  , parseTerraformStateFile
  , terraformToNodes
  )

tests :: TestTree
tests = testGroup "SoT/Terraform"
  [ testCase "fixture: aws_instance count + filter"  fixtureCount
  , testCase "fixture: web01 fields"                 fixtureWeb01
  , testCase "fixture: db01 has empty role default"  fixtureDb01Role
  , testCase "fixture: skips non-instance resources" fixtureSkipsSg
  , testCase "fixture: SoT instance via toNodes"     fixtureSoTInstance
  ]

loadFixture :: IO [Node]
loadFixture = terraformToNodes <$> parseTerraformStateFile fixturePath

fixturePath :: FilePath
fixturePath = "test/Fixtures/terraform-state.json"

findHost :: Text -> [Node] -> Node
findHost h = fromJust . lookup h . map (\n -> (hostname n, n))

fixtureCount :: IO ()
fixtureCount = do
  ns <- loadFixture
  length ns @?= 3
  -- All extracted nodes are aws_instance only
  map hostname ns @?= ["web01", "web02", "db01"]

fixtureWeb01 :: IO ()
fixtureWeb01 = do
  ns <- loadFixture
  let n = findHost "web01" ns
  ip n      @?= Just "10.0.1.10"
  role n    @?= Role "Web"
  -- Name and Role excluded from tags; remaining values sorted alphabetically by tag key.
  -- Source tags: Env=prod, Team=platform → tag values [prod, platform].
  tags n    @?= ["prod", "platform"]

fixtureDb01Role :: IO ()
fixtureDb01Role = do
  ns <- loadFixture
  let n = findHost "db01" ns
  -- No "Role" tag in fixture → "untagged" default
  role n    @?= Role "untagged"
  -- No private_ip / public_ip → ip should be Nothing
  ip n      @?= Nothing

fixtureSkipsSg :: IO ()
fixtureSkipsSg = do
  ns <- loadFixture
  -- aws_security_group must NOT produce a Node
  assertBool "no security group nodes" (not (any (\n -> "sg-" `T.isPrefixOf` hostname n) ns))

fixtureSoTInstance :: IO ()
fixtureSoTInstance = do
  ns  <- toNodes (TerraformStateFile fixturePath)
  ns' <- loadFixture
  -- The SoT typeclass instance must produce identical output to the helper.
  ns @?= ns'
