module Unit.LayoutTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Dhall
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Emit (emitFor)
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
      in assertLeftContains "collision" (emitFor layout ep)
  , testCase "emit: rejects helperPath colliding with a spec output" $
      let layout = defaultLayout { lHelperPath = "web01_spec.rb" }
          ep    = ExecutionPlan "serverspec"
                    [ Job (mkNode "web01" "Web") [pingAssertion] ]
      in assertLeftContains "collides" (emitFor layout ep)
  ]

mkNode :: Text -> Text -> Node
mkNode h r = Node h Nothing (Role r) []

-- | Smallest assertion that survives layer-3 validation: a uname command
-- check. Used so the focus stays on the layout / collision behaviour rather
-- than on emit-internal validation.
pingAssertion :: PanInfraSpec.IR.Assertion
pingAssertion = Assertion "command" "uname -a"
  (Map.fromList [("exit-status", AVNat 0)])

nodeFnDhall :: Text
nodeFnDhall =
  "\\(n : { hostname : Text, ip : Optional Text, role : Text, tags : List Text }) \
  \-> \"${n.role}/${n.hostname}_spec.rb\""

assertLeftContains :: Show a => Text -> Either Text a -> IO ()
assertLeftContains needle = \case
  Left e  | needle `T.isInfixOf` e -> pure ()
          | otherwise -> assertFailure
              ("expected error containing " <> show needle <> " but got: " <> show e)
  Right v -> assertFailure ("expected Left, got Right " <> show v)
