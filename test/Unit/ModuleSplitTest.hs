module Unit.ModuleSplitTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Scaffold (defaultServerspecScaffold)
import PanInfraSpec.IR hiding (Assertion)
import qualified PanInfraSpec.IR as IR
import PanInfraSpec.Layout (Layout (..), Sharing (..), loadLayout)

tests :: TestTree
tests = testGroup "module split"
  [ testCase "v2 layout splits assertions into per-module files"
      splitsByModule
  , testCase "merge rejects two assertions of same (kind,pk) with different module labels"
      conflictingModuleLabels
  , testCase "merge rejects mix of moduleless and module-tagged for same (kind,pk)"
      conflictingModuleLabelsMixed
  ]

mkNode :: Text -> Node
mkNode h = Node h Nothing (Role "Web") [] []

webAssert :: Text -> Maybe Text -> IR.Assertion
webAssert pk modLabel = IR.Assertion "package" pk
  (Map.singleton "installed" (AVBool True)) modLabel

emitWith :: Layout -> [IR.Assertion] -> Either Text (Map.Map FilePath Text)
emitWith layout asserts =
  let ep = ExecutionPlan "serverspec" [Job (mkNode "web01") asserts]
  in emitFor defaultServerspecScaffold layout ep

splitsByModule :: IO ()
splitsByModule = do
  layoutR <- loadLayout "test/Golden/by_module/layout.dhall"
  case layoutR of
    Left e -> assertFailure ("layout load: " <> T.unpack e)
    Right layout -> case emitWith layout
                           [ webAssert "nginx" (Just "nginx")
                           , webAssert "php"   (Just "php")
                           , webAssert "vim"   Nothing
                           ] of
      Left e   -> assertFailure (T.unpack e)
      Right fs -> do
        -- byGroupProduct: <role>/<module>_spec.rb when set, else
        -- <role>/<hostname>_spec.rb
        assertBool "Web/nginx_spec.rb produced"
          (Map.member "Web/nginx_spec.rb" fs)
        assertBool "Web/php_spec.rb produced"
          (Map.member "Web/php_spec.rb" fs)
        assertBool "Web/web01_spec.rb (no-module bucket) produced"
          (Map.member "Web/web01_spec.rb" fs)

conflictingModuleLabels :: IO ()
conflictingModuleLabels =
  let layout = Layout
        { lSpecPath = \n m -> case m of
            Just label -> "Web/" <> label <> "_" <> hostname n <> ".rb"
            Nothing    -> "Web/" <> hostname n <> ".rb"
        , lSharing  = PerHost
        }
   in case emitWith layout
         [ webAssert "nginx" (Just "nginx")
         , webAssert "nginx" (Just "web")  -- same (kind,pk), different module
         ] of
        Left e ->
          assertBool ("expected module-conflict message, got: " <> T.unpack e)
            ("conflicting module label" `T.isInfixOf` e)
        Right _ -> assertFailure "expected Left for conflicting module labels"

conflictingModuleLabelsMixed :: IO ()
conflictingModuleLabelsMixed =
  let layout = Layout
        { lSpecPath = \n m -> case m of
            Just label -> "Web/" <> label <> "_" <> hostname n <> ".rb"
            Nothing    -> "Web/" <> hostname n <> ".rb"
        , lSharing  = PerHost
        }
   in case emitWith layout
         [ webAssert "nginx" (Just "nginx")
         , webAssert "nginx" Nothing
         ] of
        Left e ->
          assertBool ("expected module-conflict message, got: " <> T.unpack e)
            ("conflicting module label" `T.isInfixOf` e)
        Right _ -> assertFailure "expected Left for mixed module labels"

