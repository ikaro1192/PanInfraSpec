-- | Backend-agnostic semantic IR.
--
-- This module is a re-export façade over three submodules split by
-- backend-affinity:
--
-- * "PanInfraSpec.IR.Inventory" — completely backend-agnostic (nodes / roles).
-- * "PanInfraSpec.IR.Selector" — backend-agnostic in shape.
-- * "PanInfraSpec.IR.Assertion" — carries 'aKind' values whose vocabulary is
--   governed by the chosen backend's schema (today only Serverspec).
--
-- Every external consumer should keep importing @PanInfraSpec.IR@ unchanged.
module PanInfraSpec.IR
  ( Role (..)
  , CustomAttribute (..)
  , Node (..)
  , CompareOp (..)
  , AttrLeaf (..)
  , AttrValue (..)
  , Expr (..)
  , Operand (..)
  , Assertion (..)
  , mkAssertion
  , Selector (..)
  , Mapping (..)
  , PlanFile (..)
  , Job (..)
  , ExecutionPlan (..)
  , SourceLoc (..)
  , roleEncoder
  , customAttributeEncoder
  , nodeEncoder
  ) where

import PanInfraSpec.IR.Inventory
  ( Role (..)
  , CustomAttribute (..)
  , Node (..)
  , roleEncoder
  , customAttributeEncoder
  , nodeEncoder
  )
import PanInfraSpec.IR.Selector  (Selector (..))
import PanInfraSpec.IR.Expr      (Expr (..), Operand (..))
import PanInfraSpec.IR.SourceLoc (SourceLoc (..))
import PanInfraSpec.IR.Assertion
  ( CompareOp (..)
  , AttrLeaf (..)
  , AttrValue (..)
  , Assertion (..)
  , mkAssertion
  , Mapping (..)
  , PlanFile (..)
  , Job (..)
  , ExecutionPlan (..)
  )
