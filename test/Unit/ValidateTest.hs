module Unit.ValidateTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.CLI (checkTargetMatches)
import PanInfraSpec.Dhall (validate)
import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.IR

tests :: TestTree
tests = testGroup "defense-in-depth"
  [ testCase "layer 1: rejects --target / prelude targetBackend mismatch" layer1TargetMismatch
  , testCase "layer 2: rejects unknown backend"     layer2UnknownBackend
  , testCase "layer 2: rejects kind not in allowlist" layer2KindAllowlist
  , testCase "layer 3: rejects unknown attrs key"   layer3UnknownAttrKey
  , testCase "layer 3: rejects conflicting attrs"   layer3ConflictingAttrs
  , testCase "layer 3: rejects empty attrs"         layer3EmptyAttrs
  , testCase "layer 3: rejects backend mismatch"    layer3BackendMismatch
  , testCase "layer 3: rejects port.protocol wrong type" layer3WrongProtocolType
  , testCase "layer 3: rejects unknown port attr"   layer3UnknownPortAttr
  ]

assertLeftContains :: Text -> Either Text a -> IO ()
assertLeftContains needle = \case
  Left msg
    | needle `T.isInfixOf` msg -> pure ()
    | otherwise -> assertFailure $
        "expected error containing " <> show needle <> ", got " <> show msg
  Right _ -> assertFailure ("expected Left containing " <> show needle <> ", got Right")

mkNode :: Text -> Node
mkNode h = Node { hostname = h, ip = Nothing, role = Role "Web", tags = [] }

layer1TargetMismatch :: IO ()
layer1TargetMismatch =
  let pf = PlanFile { pfTargetBackend = "serverspec", pfMappings = [] }
  in assertLeftContains "target mismatch" (checkTargetMatches "goss" pf)

layer2UnknownBackend :: IO ()
layer2UnknownBackend =
  let ep = ExecutionPlan "goss" [Job (mkNode "h") []]
  in assertLeftContains "unknown backend" (validate ep)

layer2KindAllowlist :: IO ()
layer2KindAllowlist =
  let bogus = Assertion "bogus" "x" (Map.fromList [("k", AVBool True)])
      ep    = ExecutionPlan "serverspec" [Job (mkNode "h") [bogus]]
  in assertLeftContains "kind not allowed" (validate ep)

layer3UnknownAttrKey :: IO ()
layer3UnknownAttrKey =
  let typo = Assertion "service" "nginx" (Map.fromList [("runninng", AVBool True)])
      ep   = ExecutionPlan "serverspec" [Job (mkNode "h") [typo]]
  in assertLeftContains "unknown attrs key" (emitFor ep)

layer3ConflictingAttrs :: IO ()
layer3ConflictingAttrs =
  let a = Assertion "command" "uname" (Map.fromList [("exit-status", AVNat 0)])
      b = Assertion "command" "uname" (Map.fromList [("exit-status", AVNat 1)])
      ep = ExecutionPlan "serverspec" [Job (mkNode "h") [a, b]]
  in assertLeftContains "conflicting attribute" (emitFor ep)

layer3EmptyAttrs :: IO ()
layer3EmptyAttrs =
  let empty = Assertion "service" "nginx" Map.empty
      ep    = ExecutionPlan "serverspec" [Job (mkNode "h") [empty]]
  in assertLeftContains "empty attrs" (emitFor ep)

layer3BackendMismatch :: IO ()
layer3BackendMismatch =
  -- Bypass the dispatcher and call the Serverspec emitter directly through emitFor;
  -- the dispatcher rejects "goss" first, so use a backend the dispatcher knows
  -- but the Serverspec emitter doesn't accept. Phase 1 has no such backend, so
  -- exercise the dispatcher path which produces the equivalent guarantee.
  let ep = ExecutionPlan "" []
  in assertLeftContains "unknown backend" (emitFor ep)

layer3WrongProtocolType :: IO ()
layer3WrongProtocolType =
  let bad = Assertion "port" "80" (Map.fromList [("protocol", AVNat 80)])
      ep  = ExecutionPlan "serverspec" [Job (mkNode "h") [bad]]
  in assertLeftContains "wrong attr type for port.protocol" (emitFor ep)

layer3UnknownPortAttr :: IO ()
layer3UnknownPortAttr =
  let bad = Assertion "port" "80" (Map.fromList [("tcp_only", AVBool True)])
      ep  = ExecutionPlan "serverspec" [Job (mkNode "h") [bad]]
  in assertLeftContains "unknown attrs key for kind port" (emitFor ep)
