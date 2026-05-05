-- | Compile-time guarantee that the @PanInfraSpec.IR@ façade re-exports the
-- exact same types defined in the three submodules. If a submodule defined a
-- shadow copy, these annotations would fail to type-check.
module Unit.IR.SplitTest (tests) where

import qualified Data.Map.Strict as Map
import Test.Tasty
import Test.Tasty.HUnit

import qualified PanInfraSpec.IR             as IR
import qualified PanInfraSpec.IR.Assertion   as IRA
import qualified PanInfraSpec.IR.Inventory   as IRI
import qualified PanInfraSpec.IR.Selector    as IRS

tests :: TestTree
tests = testGroup "IR.Split (façade re-export identity)"
  [ testCase "Inventory types are re-exported unchanged" inventoryIdentity
  , testCase "Selector type is re-exported unchanged"    selectorIdentity
  , testCase "Assertion types are re-exported unchanged" assertionIdentity
  , testCase "Mapping/PlanFile cross-module wiring"      mappingWiring
  ]

inventoryIdentity :: Assertion
inventoryIdentity = do
  let r = IRI.Role "Web" :: IR.Role
      ca = IRI.CustomAttribute "x" "y" :: IR.CustomAttribute
      n  = IRI.Node "h" Nothing r [] [ca] :: IR.Node
  IR.unRole r          @?= "Web"
  IR.caName     ca     @?= "x"
  IR.caCommand  ca     @?= "y"
  IR.hostname   n      @?= "h"
  IR.role       n      @?= r

selectorIdentity :: Assertion
selectorIdentity = do
  let s = IRS.SelAll :: IR.Selector
  case s of
    IR.SelAll -> pure ()
    _         -> assertFailure "SelAll re-export mismatch"

assertionIdentity :: Assertion
assertionIdentity = do
  let a = IRA.Assertion
            { IRA.aKind       = "package"
            , IRA.aPrimaryKey = "nginx"
            , IRA.aAttrs      = Map.empty
            , IRA.aModule     = Nothing
            , IRA.aSourceLocs = []
            } :: IR.Assertion
  IR.aKind a @?= "package"

mappingWiring :: Assertion
mappingWiring = do
  let a  = IRA.mkAssertion "package" "nginx" Map.empty Nothing
      m  = IRA.Mapping IRS.SelAll [a] :: IR.Mapping
      pf = IRA.PlanFile "serverspec" [m] :: IR.PlanFile
      n  = IRI.Node "h" Nothing (IRI.Role "Web") [] []
      j  = IRA.Job n [a] :: IR.Job
      ep = IRA.ExecutionPlan "serverspec" [j] :: IR.ExecutionPlan
  length (IR.pfMappings pf) @?= 1
  length (IR.epJobs ep)     @?= 1
