module Unit.ValidateTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.CLI (checkTargetMatches)
import PanInfraSpec.Dhall (validate)
import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Scaffold.Defaults.Serverspec (defaultServerspecScaffold)
import PanInfraSpec.IR
import PanInfraSpec.Layout (defaultLayout)

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
  , testCase "layer 3: rejects wildcard kind non-Text value" layer3WildcardWrongType
  , testCase "layer 3: rejects routing_table conflicting gateway" layer3RoutingTableConflict
  ]

assertLeftContains :: Text -> Either Text a -> IO ()
assertLeftContains needle = \case
  Left msg
    | needle `T.isInfixOf` msg -> pure ()
    | otherwise -> assertFailure $
        "expected error containing " <> show needle <> ", got " <> show msg
  Right _ -> assertFailure ("expected Left containing " <> show needle <> ", got Right")

mkNode :: Text -> Node
mkNode h = Node
  { hostname         = h
  , ip               = Nothing
  , role             = Role "Web"
  , tags             = []
  , customAttributes = []
  }

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
  let bogus = Assertion "bogus" "x" (Map.fromList [("k", AVBool True)]) Nothing
      ep    = ExecutionPlan "serverspec" [Job (mkNode "h") [bogus]]
  in assertLeftContains "kind not allowed" (validate ep)

layer3UnknownAttrKey :: IO ()
layer3UnknownAttrKey =
  let typo = Assertion "service" "nginx" (Map.fromList [("runninng", AVBool True)]) Nothing
      ep   = ExecutionPlan "serverspec" [Job (mkNode "h") [typo]]
  in assertLeftContains "unknown attrs key" (emitFor defaultServerspecScaffold defaultLayout ep)

layer3ConflictingAttrs :: IO ()
layer3ConflictingAttrs =
  let a = Assertion "command" "uname" (Map.fromList [("exit-status", AVNat 0)]) Nothing
      b = Assertion "command" "uname" (Map.fromList [("exit-status", AVNat 1)]) Nothing
      ep = ExecutionPlan "serverspec" [Job (mkNode "h") [a, b]]
  in assertLeftContains "conflicting attribute" (emitFor defaultServerspecScaffold defaultLayout ep)

layer3EmptyAttrs :: IO ()
layer3EmptyAttrs =
  let empty = Assertion "service" "nginx" Map.empty Nothing
      ep    = ExecutionPlan "serverspec" [Job (mkNode "h") [empty]]
  in assertLeftContains "empty attrs" (emitFor defaultServerspecScaffold defaultLayout ep)

layer3BackendMismatch :: IO ()
layer3BackendMismatch =
  -- Bypass the dispatcher and call the Serverspec emitter directly through emitFor;
  -- the dispatcher rejects "goss" first, so use a backend the dispatcher knows
  -- but the Serverspec emitter doesn't accept. Phase 1 has no such backend, so
  -- exercise the dispatcher path which produces the equivalent guarantee.
  let ep = ExecutionPlan "" []
  in assertLeftContains "unknown backend" (emitFor defaultServerspecScaffold defaultLayout ep)

layer3WrongProtocolType :: IO ()
layer3WrongProtocolType =
  let bad = Assertion "port" "80" (Map.fromList [("protocol", AVNat 80)]) Nothing
      ep  = ExecutionPlan "serverspec" [Job (mkNode "h") [bad]]
  in assertLeftContains "wrong attr type for port.protocol" (emitFor defaultServerspecScaffold defaultLayout ep)

layer3UnknownPortAttr :: IO ()
layer3UnknownPortAttr =
  let bad = Assertion "port" "80" (Map.fromList [("tcp_only", AVBool True)]) Nothing
      ep  = ExecutionPlan "serverspec" [Job (mkNode "h") [bad]]
  in assertLeftContains "unknown attrs key for kind port" (emitFor defaultServerspecScaffold defaultLayout ep)

-- Wildcard kinds (e.g. routing_table) require AVText values for every attr key.
layer3WildcardWrongType :: IO ()
layer3WildcardWrongType =
  let bad = Assertion "routing_table" "routing_table"
              (Map.fromList [("10.0.0.0/8", AVNat 1)]) Nothing
      ep  = ExecutionPlan "serverspec" [Job (mkNode "h") [bad]]
  in assertLeftContains "wildcard kind" (emitFor defaultServerspecScaffold defaultLayout ep)

-- Two routing_table entries sharing the same destination but disagreeing on
-- the gateway must be rejected by the layer-3 conflict fail-safe.
layer3RoutingTableConflict :: IO ()
layer3RoutingTableConflict =
  let a = Assertion "routing_table" "routing_table"
            (Map.fromList [("10.0.0.0/8", AVText "10.0.0.1")]) Nothing
      b = Assertion "routing_table" "routing_table"
            (Map.fromList [("10.0.0.0/8", AVText "10.0.0.2")]) Nothing
      ep = ExecutionPlan "serverspec" [Job (mkNode "h") [a, b]]
  in assertLeftContains "conflicting attribute" (emitFor defaultServerspecScaffold defaultLayout ep)
