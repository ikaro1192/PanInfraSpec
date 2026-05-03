module Unit.LayoutTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Dhall
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Scaffold (Scaffold, applyServerspecLayoutPaths, defaultServerspecScaffold)
import PanInfraSpec.IR
import PanInfraSpec.Layout

tests :: TestTree
tests = testGroup "Layout"
  [ testCase "defaultLayout: hostname maps to <hostname>_spec.rb" $
      assertEqual "" "web01_spec.rb" (lSpecPath defaultLayout (mkNode "web01" "Web"))
  , testCase "defaultLayout: helper / Rakefile fixed"             $ do
      assertEqual "" "spec_helper.rb" (lHelperPath   defaultLayout)
      assertEqual "" "Rakefile"       (lRakefilePath defaultLayout)
  , testCase "validateLayoutPath: empty rejected" $
      assertLeftContains "empty" (validateLayoutPath "")
  , testCase "validateLayoutPath: POSIX absolute rejected" $
      assertLeftContains "absolute" (validateLayoutPath "/etc/passwd")
  , testCase "validateLayoutPath: Windows drive-letter absolute rejected" $
      assertLeftContains "absolute" (validateLayoutPath "C:\\Windows\\foo.rb")
  , testCase "validateLayoutPath: leading backslash rejected" $
      assertLeftContains "absolute" (validateLayoutPath "\\foo\\bar.rb")
  , testCase "validateLayoutPath: traversal rejected (forward slash)" $
      assertLeftContains "escapes" (validateLayoutPath "../escape/here.rb")
  , testCase "validateLayoutPath: traversal rejected (backslash)" $
      assertLeftContains "escapes" (validateLayoutPath "a\\..\\b.rb")
  , testCase "validateLayoutPath: NUL rejected" $
      assertLeftContains "forbidden" (validateLayoutPath "ok\NULnope.rb")
  , testCase "validateLayoutPath: nested OK" $
      assertEqual "" (Right "Web/web01_spec.rb") (validateLayoutPath "Web/web01_spec.rb")
  , testCase "loadLayout: function value decodes to a closure" $ do
      f <- Dhall.input
        (Dhall.function nodeEncoder Dhall.strictText)
        nodeFnDhall
      assertEqual "by-role" "Web/web01_spec.rb" (f (mkNode "web01" "Web"))
      assertEqual "by-role for DB" "DBPrimary/db01_spec.rb" (f (mkNode "db01" "DBPrimary"))
  , testCase "emit: rejects non-injective specPath (collision)" $
      let layout = defaultLayout { lSpecPath = \_ -> "all_specs.rb" }
          ep    = ExecutionPlan "serverspec"
                    [ Job (mkNode "web01" "Web") [pingAssertion]
                    , Job (mkNode "web02" "Web") [pingAssertion]
                    ]
      in assertLeftContains "collision"
           (emitFor (scaffoldFromLayout layout) layout ep)
  , testCase "emit: rejects helperPath colliding with a spec output" $
      let layout = defaultLayout { lHelperPath = "web01_spec.rb" }
          ep    = ExecutionPlan "serverspec"
                    [ Job (mkNode "web01" "Web") [pingAssertion] ]
      in assertLeftContains "collides"
           (emitFor (scaffoldFromLayout layout) layout ep)
  , testCase "isLayoutV2: defaultLayout is v1"               $
      assertBool "" (not (isLayoutV2 defaultLayout))
  , testCase "applySpecPath: v1 layout ignores module label" $
      assertEqual "" "web01_spec.rb"
        (applySpecPath defaultLayout (mkNode "web01" "Web") (Just "nginx"))
  , testCase "loadLayout: v1 byRole still works"             $ do
      r <- loadLayout "test/Golden/by_role/layout.dhall"
      case r of
        Left e  -> assertFailure (T.unpack e)
        Right l -> do
          assertBool "v1 expected" (not (isLayoutV2 l))
          assertEqual "byRole path"
            "Web/web01_spec.rb"
            (applySpecPath l (mkNode "web01" "Web") Nothing)
  , testCase "loadLayout: v2 layout from inline Dhall fixture" v2LoadInline
  ]

v2LoadInline :: IO ()
v2LoadInline = do
  let path = "test/Golden/by_module/layout.dhall"
  r <- loadLayout path
  case r of
    Left e  -> assertFailure ("loadLayout v2 failed: " <> T.unpack e)
    Right l -> do
      assertBool "v2 expected" (isLayoutV2 l)
      -- byGroupProduct: with module Some "nginx", expect <role>/nginx_spec.rb
      assertEqual "with module"
        "Web/nginx_spec.rb"
        (applySpecPath l (mkNode "web01" "Web") (Just "nginx"))
      -- without module: <role>/<hostname>_spec.rb
      assertEqual "without module"
        "Web/web01_spec.rb"
        (applySpecPath l (mkNode "web01" "Web") Nothing)

-- | Mirror the CLI default-scaffold behaviour: when no @--scaffold@ is given,
-- the v1 'Layout' fields rewrite the well-known scaffold file paths.
scaffoldFromLayout :: Layout -> Scaffold
scaffoldFromLayout layout = applyServerspecLayoutPaths
  (lHelperPath   layout)
  (lRakefilePath layout)
  defaultServerspecScaffold

mkNode :: Text -> Text -> Node
mkNode h r = Node h Nothing (Role r) [] []

-- | Smallest assertion that survives layer-3 validation: a uname command
-- check. Used so the focus stays on the layout / collision behaviour rather
-- than on emit-internal validation.
pingAssertion :: PanInfraSpec.IR.Assertion
pingAssertion = Assertion "command" "uname -a"
  (Map.fromList [("exit-status", AVNat 0)]) Nothing

nodeFnDhall :: Text
nodeFnDhall =
  "\\(n : { hostname : Text, ip : Optional Text, role : Text, tags : List Text, customAttributes : List { name : Text, command : Text } }) \
  \-> \"${n.role}/${n.hostname}_spec.rb\""

assertLeftContains :: Show a => Text -> Either Text a -> IO ()
assertLeftContains needle = \case
  Left e  | needle `T.isInfixOf` e -> pure ()
          | otherwise -> assertFailure
              ("expected error containing " <> show needle <> " but got: " <> show e)
  Right v -> assertFailure ("expected Left, got Right " <> show v)
