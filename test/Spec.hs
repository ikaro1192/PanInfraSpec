module Main (main) where

import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Text.Encoding as TE
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)

import PanInfraSpec.Dhall (loadInventory, loadPlan, validate)
import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.IR (PlanFile (..))
import PanInfraSpec.Resolve (resolve)

import qualified Property.EmitTest
import qualified Roundtrip.DhallEncodingTest
import qualified SoT.TerraformTest
import qualified Synth.HundredHostsTest
import qualified Unit.ValidateTest

main :: IO ()
main = defaultMain $ testGroup "paninfraspec"
  [ Unit.ValidateTest.tests
  , Roundtrip.DhallEncodingTest.tests
  , Property.EmitTest.tests
  , Synth.HundredHostsTest.tests
  , SoT.TerraformTest.tests
  , goldenTests
  ]

goldenTests :: TestTree
goldenTests = testGroup "golden"
  [ goldenFile "web01_spec.rb"
  , goldenFile "spec_helper.rb"
  , goldenFile "Rakefile"
  ]

goldenFile :: FilePath -> TestTree
goldenFile name =
  goldenVsString name ("test/Golden/expected/" <> name) (generate name)

generate :: FilePath -> IO LBS.ByteString
generate name = do
  nodes <- loadInventory "test/Golden/inventory.dhall"
  pf    <- loadPlan      "test/Golden/plan.dhall"
  let plan = resolve "serverspec" nodes (pfMappings pf)
  case validate plan >>= emitFor of
    Left e -> error ("emit failed: " <> show e)
    Right outs -> case Map.lookup name outs of
      Just t  -> pure (LBS.fromStrict (TE.encodeUtf8 t))
      Nothing -> error ("missing output file: " <> name)
