module Unit.RegistryTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Emit (backendAllowedKinds, emitFor, knownBackends)
import PanInfraSpec.Emit.SourceMap (defaultEmitOptions)
import PanInfraSpec.IR (ExecutionPlan (..))
import PanInfraSpec.Layout (defaultLayout)
import PanInfraSpec.Scaffold.Defaults.Serverspec (defaultServerspecScaffold)

tests :: TestTree
tests = testGroup "backend registry"
  [ testCase "knownBackends lists the registered backends" knownBackendsIsServerspec
  , testCase "backendAllowedKinds lifts from the registry" allowedKindsFromRegistry
  , testCase "backendAllowedKinds returns [] for unregistered names" allowedKindsUnknown
  , testCase "emitFor returns 'unknown backend: <name>' for unregistered names" emitForUnknown
  ]

knownBackendsIsServerspec :: IO ()
knownBackendsIsServerspec =
  knownBackends @?= ["serverspec"]

allowedKindsFromRegistry :: IO ()
allowedKindsFromRegistry = do
  let kinds = backendAllowedKinds "serverspec"
  assertBool "service is allowed"          ("service"          `elem` kinds)
  assertBool "package is allowed"          ("package"          `elem` kinds)
  assertBool "docker_container is allowed" ("docker_container" `elem` kinds)

allowedKindsUnknown :: IO ()
allowedKindsUnknown =
  backendAllowedKinds "no_such_backend" @?= []

emitForUnknown :: IO ()
emitForUnknown =
  let ep = ExecutionPlan "ghost" []
  in emitFor defaultServerspecScaffold defaultLayout ep defaultEmitOptions
       @?= Left "unknown backend: ghost"
