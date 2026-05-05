module Unit.SourceLocTest (tests) where

import qualified Control.Monad.Trans.State.Strict as State
import qualified Data.Map.Strict as Map
import qualified Data.Text.IO as TIO
import System.FilePath (takeDirectory)
import Test.Tasty
import Test.Tasty.HUnit

import qualified Dhall.Import as Import
import qualified Dhall.Parser as Parser

import PanInfraSpec.Dhall.SourceMap (extractAssertionLocs)
import PanInfraSpec.IR.SourceLoc (SourceLoc (..))

tests :: TestTree
tests = testGroup "Dhall.SourceMap"
  [ testCase "extractAssertionLocs indexes assertions by (mappingIdx, assertionIdx)" $ do
      locs <- loadFixtureLocs fixturePath
      Map.size locs @?= 3
      assertHas locs (0, 0)
      assertHas locs (1, 0)
      assertHas locs (1, 1)

  , testCase "each loc points back into the original Dhall plan file" $ do
      locs <- loadFixtureLocs fixturePath
      case Map.lookup (0, 0) locs of
        Just loc -> do
          slFile loc      @?= fixturePath
          slStartLine loc @?= 12
          assertBool "slText is non-empty" (not (null (show (slText loc))))
        Nothing -> assertFailure "expected loc at (0,0)"

  , testCase "Web/nginx assertion locations differ" $ do
      locs <- loadFixtureLocs fixturePath
      case (Map.lookup (1, 0) locs, Map.lookup (1, 1) locs) of
        (Just a, Just b) -> assertBool "nginx package and service are on different lines"
                              (slStartLine a /= slStartLine b)
        _ -> assertFailure "expected locs at (1,0) and (1,1)"
  ]

fixturePath :: FilePath
fixturePath = "test/Fixtures/source-loc/plan.dhall"

loadFixtureLocs :: FilePath -> IO (Map.Map (Int, Int) SourceLoc)
loadFixtureLocs path = do
  raw      <- TIO.readFile path
  parsed   <- case Parser.exprFromText path raw of
    Left  e -> assertFailure ("parse failed: " <> show e) >> error "unreachable"
    Right e -> pure e
  resolved <- State.evalStateT (Import.loadWith parsed)
                (Import.emptyStatus (takeDirectory path))
  pure (extractAssertionLocs path resolved)

assertHas :: Map.Map (Int, Int) SourceLoc -> (Int, Int) -> Assertion
assertHas locs idx =
  assertBool ("expected key " <> show idx <> " in locs map")
             (Map.member idx locs)
