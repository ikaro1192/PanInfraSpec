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
import PanInfraSpec.Layout (Layout (..), defaultLayout, loadLayout)

tests :: TestTree
tests = testGroup "module split"
  [ testCase "v1 layout collapses module-tagged assertions into one file"
      v1CollapsesModules
  , testCase "v2 layout splits assertions into per-module files"
      v2SplitsByModule
  , testCase "merge rejects two assertions of same (kind,pk) with different module labels"
      conflictingModuleLabels
  , testCase "merge rejects mix of moduleless and module-tagged for same (kind,pk)"
      conflictingModuleLabelsMixed
  , testCase "v1 layout tolerates same-(kind,pk) cross-module mix (module ignored)"
      v1IgnoresModuleMismatch
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

v1CollapsesModules :: IO ()
v1CollapsesModules =
  case emitWith defaultLayout
         [ webAssert "nginx" (Just "nginx")
         , webAssert "php"   (Just "php")
         , webAssert "vim"   Nothing
         ] of
    Left e   -> assertFailure (T.unpack e)
    Right fs -> do
      -- Default v1 layout: one host = one file, all packages in it.
      assertBool "exactly one host file"
        (Map.member "web01_spec.rb" fs)
      let body = fs Map.! "web01_spec.rb"
      assertBool "nginx package present" ("'nginx'" `T.isInfixOf` body)
      assertBool "php package present"   ("'php'"   `T.isInfixOf` body)
      assertBool "vim package present"   ("'vim'"   `T.isInfixOf` body)

v2SplitsByModule :: IO ()
v2SplitsByModule = do
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
  case emitWith defaultLayout { lSpecPathByModule =
         Just (\n m -> case m of
           Just label -> "Web/" <> label <> "_" <> hostname n <> ".rb"
           Nothing    -> "Web/" <> hostname n <> ".rb")
       }
         [ webAssert "nginx" (Just "nginx")
         , webAssert "nginx" (Just "web")  -- same (kind,pk), different module
         ] of
    Left e ->
      assertBool ("expected module-conflict message, got: " <> T.unpack e)
        ("conflicting module label" `T.isInfixOf` e)
    Right _ -> assertFailure "expected Left for conflicting module labels"

conflictingModuleLabelsMixed :: IO ()
conflictingModuleLabelsMixed =
  case emitWith defaultLayout { lSpecPathByModule =
         Just (\n m -> case m of
           Just label -> "Web/" <> label <> "_" <> hostname n <> ".rb"
           Nothing    -> "Web/" <> hostname n <> ".rb")
       }
         [ webAssert "nginx" (Just "nginx")
         , webAssert "nginx" Nothing
         ] of
    Left e ->
      assertBool ("expected module-conflict message, got: " <> T.unpack e)
        ("conflicting module label" `T.isInfixOf` e)
    Right _ -> assertFailure "expected Left for mixed module labels"

v1IgnoresModuleMismatch :: IO ()
v1IgnoresModuleMismatch =
  -- v1 normalises modules to Nothing before merge, so cross-module
  -- assertions for the same (kind,pk) are merged silently. This is the
  -- pre-module behaviour and must keep working.
  case emitWith defaultLayout
         [ webAssert "nginx" (Just "nginx")
         , webAssert "nginx" (Just "web")
         ] of
    Left e   -> assertFailure ("v1 should not error: " <> T.unpack e)
    Right fs -> assertBool "single file produced"
                  (Map.member "web01_spec.rb" fs)
