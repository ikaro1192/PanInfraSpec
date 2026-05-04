module Unit.LayoutTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Dhall
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Scaffold (OutputFile (..), defaultServerspecScaffold, sStaticFiles)
import PanInfraSpec.IR
import PanInfraSpec.Layout

tests :: TestTree
tests = testGroup "Layout"
  [ testCase "defaultLayout: hostname maps to <hostname>_spec.rb (no module)" $
      assertEqual ""
        "web01_spec.rb"
        (lSpecPath defaultLayout (mkNode "web01" "Web") Nothing)
  , testCase "defaultLayout: hostname + module → <hostname>_<module>_spec.rb" $
      assertEqual ""
        "web01_nginx_spec.rb"
        (lSpecPath defaultLayout (mkNode "web01" "Web") (Just "nginx"))
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
      let layout = Layout { lSpecPath = \_ _ -> "all_specs.rb", lSharing = PerHost }
          ep    = ExecutionPlan "serverspec"
                    [ Job (mkNode "web01" "Web") [pingAssertion]
                    , Job (mkNode "web02" "Web") [pingAssertion]
                    ]
      in assertLeftContains "collision"
           (emitFor defaultServerspecScaffold layout ep)
  , testCase "emit: rejects scaffold static file colliding with a spec output" $
      let scaffold = defaultServerspecScaffold
            { sStaticFiles =
                OutputFile "web01_spec.rb" "" : sStaticFiles defaultServerspecScaffold
            }
          ep = ExecutionPlan "serverspec"
                 [ Job (mkNode "web01" "Web") [pingAssertion] ]
      in assertLeftContains "collides"
           (emitFor scaffold defaultLayout ep)
  , testCase "loadLayout: byGroupProduct fixture works" byGroupProductLoad
  -- PerRole sharing: role-shared spec file across multiple hosts ----------
  , testCase "PerRole: identical content across hosts merges into one file"
      perRoleMergesIdenticalContent
  , testCase "PerRole: differing content across hosts is an error"
      perRoleRejectsDifferingContent
  , testCase "PerRole: customAttributes rejected"
      perRoleRejectsCustomAttributes
  , testCase "loadLayout: byGroupProduct fixture is PerRole" byGroupProductIsPerRole
  ]

-- | Two hosts in the same role with the same module-tagged assertion: PerRole
-- collapses the role-shared path (`Web/nginx_spec.rb`) into a single output.
perRoleMergesIdenticalContent :: IO ()
perRoleMergesIdenticalContent =
  let layout = Layout
        { lSpecPath = \n m -> case m of
            Just label -> unRole (role n) <> "/" <> label <> "_spec.rb"
            Nothing    -> unRole (role n) <> "/" <> hostname n <> "_spec.rb"
        , lSharing  = PerRole
        }
      moduleLabel = Just "nginx"
      asserts =
        [ Assertion "command" "uname -a"
            (Map.fromList [("exit-status", AVNat 0)]) moduleLabel
        ]
      ep = ExecutionPlan "serverspec"
             [ Job (mkNode "web01" "Web") asserts
             , Job (mkNode "web02" "Web") asserts
             ]
  in case emitFor defaultServerspecScaffold layout ep of
       Left e     -> assertFailure ("expected merge, got error: " <> T.unpack e)
       Right outs -> do
         assertBool "Web/nginx_spec.rb missing" $
           Map.member "Web/nginx_spec.rb" outs
         assertBool "no per-host nginx files should leak" $
           not (Map.member "Web/web01_nginx_spec.rb" outs)

-- | Same path, different assertion content (e.g. one host has an extra check)
-- → PerRole cannot reconcile and must fail loudly.
perRoleRejectsDifferingContent :: IO ()
perRoleRejectsDifferingContent =
  let layout = Layout
        { lSpecPath = \n m -> case m of
            Just label -> unRole (role n) <> "/" <> label <> "_spec.rb"
            Nothing    -> unRole (role n) <> "/" <> hostname n <> "_spec.rb"
        , lSharing  = PerRole
        }
      moduleLabel = Just "nginx"
      base = Assertion "command" "uname -a"
               (Map.fromList [("exit-status", AVNat 0)]) moduleLabel
      extra = Assertion "command" "hostname"
                (Map.fromList [("exit-status", AVNat 0)]) moduleLabel
      ep = ExecutionPlan "serverspec"
             [ Job (mkNode "web01" "Web") [base]
             , Job (mkNode "web02" "Web") [base, extra]
             ]
  in assertLeftContains "differing spec contents"
       (emitFor defaultServerspecScaffold layout ep)

-- | PerRole layout + a host with non-empty customAttributes → emit refuses
-- because per-host preamble values cannot live in a role-shared file.
perRoleRejectsCustomAttributes :: IO ()
perRoleRejectsCustomAttributes =
  let layout = Layout
        { lSpecPath = \n m -> case m of
            Just label -> unRole (role n) <> "/" <> label <> "_spec.rb"
            Nothing    -> unRole (role n) <> "/" <> hostname n <> "_spec.rb"
        , lSharing  = PerRole
        }
      asserts = [ Assertion "command" "uname -a"
                    (Map.fromList [("exit-status", AVNat 0)]) (Just "nginx") ]
      noisyNode = (mkNode "web01" "Web")
        { customAttributes = [CustomAttribute "ram" "free -k"] }
      ep = ExecutionPlan "serverspec" [ Job noisyNode asserts ]
  in assertLeftContains "PerRole layout does not support customAttributes"
       (emitFor defaultServerspecScaffold layout ep)

byGroupProductLoad :: IO ()
byGroupProductLoad = do
  let path = "test/Golden/by_module/layout.dhall"
  r <- loadLayout path
  case r of
    Left e  -> assertFailure ("loadLayout failed: " <> T.unpack e)
    Right l -> do
      -- byGroupProduct: with module Some "nginx", expect <role>/nginx_spec.rb
      assertEqual "with module"
        "Web/nginx_spec.rb"
        (applySpecPath l (mkNode "web01" "Web") (Just "nginx"))
      -- without module: <role>/<hostname>_spec.rb
      assertEqual "without module"
        "Web/web01_spec.rb"
        (applySpecPath l (mkNode "web01" "Web") Nothing)

-- | byGroupProduct now declares itself PerRole. Make sure the Dhall fixture
-- decoder picks that up so the role-shared spec semantics are wired through.
byGroupProductIsPerRole :: IO ()
byGroupProductIsPerRole = do
  r <- loadLayout "test/Golden/by_module/layout.dhall"
  case r of
    Left e  -> assertFailure ("loadLayout failed: " <> T.unpack e)
    Right l -> assertEqual "" PerRole (lSharing l)

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
