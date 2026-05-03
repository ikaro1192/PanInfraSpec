module Main (main) where

import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Text.Encoding as TE
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)

import PanInfraSpec.Dhall (loadInventory, loadPlan, validate)
import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.IR (PlanFile (..))
import PanInfraSpec.Layout (Layout, defaultLayout, loadLayout)
import PanInfraSpec.Resolve (resolve)

import qualified Property.EmitTest
import qualified Roundtrip.DhallEncodingTest
import qualified SoT.TerraformTest
import qualified Synth.HundredHostsTest
import qualified Unit.LayoutTest
import qualified Unit.ValidateTest

main :: IO ()
main = defaultMain $ testGroup "paninfraspec"
  [ Unit.ValidateTest.tests
  , Unit.LayoutTest.tests
  , Roundtrip.DhallEncodingTest.tests
  , Property.EmitTest.tests
  , Synth.HundredHostsTest.tests
  , SoT.TerraformTest.tests
  , flatGoldenTests
  , byRoleGoldenTests
  ]

flatGoldenTests :: TestTree
flatGoldenTests = testGroup "golden (flat / defaultLayout)"
  [ flatGolden "web01_spec.rb"
  , flatGolden "spec_helper.rb"
  , flatGolden "Rakefile"
  ]

flatGolden :: FilePath -> TestTree
flatGolden name = goldenVsString
  name
  ("test/Golden/expected/" <> name)
  (generateFlat name)

generateFlat :: FilePath -> IO LBS.ByteString
generateFlat = generateWith
  "test/Golden/inventory.dhall"
  "test/Golden/plan.dhall"
  (pure defaultLayout)

byRoleGoldenTests :: TestTree
byRoleGoldenTests = testGroup "golden (by-role layout)"
  [ byRoleGolden "Web/web01_spec.rb"
  , byRoleGolden "DBPrimary/db01_spec.rb"
  , byRoleGolden "spec_helper.rb"
  , byRoleGolden "Rakefile"
  ]

byRoleGolden :: FilePath -> TestTree
byRoleGolden name = goldenVsString
  name
  ("test/Golden/expected/by_role/" <> name)
  (generateByRole name)

generateByRole :: FilePath -> IO LBS.ByteString
generateByRole = generateWith
  "test/Golden/by_role/inventory.dhall"
  "test/Golden/by_role/plan.dhall"
  (loadByRoleLayout "test/Golden/by_role/layout.dhall")
  where
    loadByRoleLayout p = do
      r <- loadLayout p
      case r of
        Right l -> pure l
        Left  e -> error ("loadLayout: " <> show e)

generateWith :: FilePath -> FilePath -> IO Layout -> FilePath -> IO LBS.ByteString
generateWith invPath planPath getLayout name = do
  nodes  <- loadInventory invPath
  pf     <- loadPlan      planPath
  layout <- getLayout
  let plan = resolve "serverspec" nodes (pfMappings pf)
  case validate plan >>= emitFor layout of
    Left e -> error ("emit failed: " <> show e)
    Right outs -> case Map.lookup name outs of
      Just t  -> pure (LBS.fromStrict (TE.encodeUtf8 t))
      Nothing -> error ("missing output file: " <> name)
