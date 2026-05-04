module PanInfraSpec.IR.Assertion
  ( CompareOp (..)
  , AttrLeaf (..)
  , AttrValue (..)
  , Assertion (..)
  , Mapping (..)
  , PlanFile (..)
  , Job (..)
  , ExecutionPlan (..)
  ) where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Numeric.Natural (Natural)
import GHC.Generics (Generic)

import qualified Dhall

import PanInfraSpec.IR.Inventory (Node)
import PanInfraSpec.IR.Selector  (Selector)

-- | Comparison operator for 'AVCompare'. Mirrors the Dhall union
-- @< Lt | Le | Gt | Ge | Eq | Match >@. Used for matchers like
-- @validity_in_days should be > 30@ and @value should match /pattern/@.
data CompareOp = OpLt | OpLe | OpGt | OpGe | OpEq | OpMatch
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall CompareOp where
  autoWith _ = Dhall.union
    (  (OpLt    <$ Dhall.constructor "Lt"    Dhall.unit)
    <> (OpLe    <$ Dhall.constructor "Le"    Dhall.unit)
    <> (OpGt    <$ Dhall.constructor "Gt"    Dhall.unit)
    <> (OpGe    <$ Dhall.constructor "Ge"    Dhall.unit)
    <> (OpEq    <$ Dhall.constructor "Eq"    Dhall.unit)
    <> (OpMatch <$ Dhall.constructor "Match" Dhall.unit)
    )

-- | Scalar leaf carried inside compound 'AttrValue' constructors
-- ('AVList', 'AVRecord', 'AVCompare'). Dhall lacks recursive types, so the
-- nested element type is a separate, non-recursive union (the same trick
-- used for 'PanInfraSpec.IR.Selector.Selector' boolean composition).
data AttrLeaf
  = ALText     Text
  | ALNat      Natural
  | ALBool     Bool
  | ALSymbol   Text
  | ALRegex    Text   -- ^ Ruby regex literal payload (without surrounding @/.../@).
  | ALRubyExpr Text   -- ^ Bare Ruby expression. Emitted unquoted so the value
                      -- can flow into a matcher that compares against a Ruby
                      -- variable or arithmetic expression (e.g.
                      -- @paninfraspec_total_ram_kb.to_i * 1024 * 70 \/ 100@).
                      -- Unlike 'ALText', no escaping or surrounding quotes
                      -- are added — the user is asserting "this is Ruby".
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall AttrLeaf where
  autoWith _ = Dhall.union
    (  (ALText     <$> Dhall.constructor "ALText"     Dhall.auto)
    <> (ALNat      <$> Dhall.constructor "ALNat"      Dhall.auto)
    <> (ALBool     <$> Dhall.constructor "ALBool"     Dhall.auto)
    <> (ALSymbol   <$> Dhall.constructor "ALSymbol"   Dhall.auto)
    <> (ALRegex    <$> Dhall.constructor "ALRegex"    Dhall.auto)
    <> (ALRubyExpr <$> Dhall.constructor "ALRubyExpr" Dhall.auto)
    )

-- | Attribute value carried inside an 'Assertion'. Mirrors the Dhall union
-- declared in @dhall/Serverspec.dhall@. The compound constructors
-- ('AVList', 'AVRecord', 'AVCompare') carry 'AttrLeaf' instead of
-- 'AttrValue' to stay within Dhall's non-recursive type system.
data AttrValue
  = AVText    Text
  | AVNat     Natural
  | AVBool    Bool
  | AVSymbol  Text
  | AVList    [AttrLeaf]
  | AVRecord  (Map Text AttrLeaf)
  | AVCompare CompareOp AttrLeaf
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall AttrValue where
  autoWith _ = Dhall.union
    (  (AVText    <$> Dhall.constructor "AVText"    Dhall.auto)
    <> (AVNat     <$> Dhall.constructor "AVNat"     Dhall.auto)
    <> (AVBool    <$> Dhall.constructor "AVBool"    Dhall.auto)
    <> (AVSymbol  <$> Dhall.constructor "AVSymbol"  Dhall.auto)
    <> (AVList    <$> Dhall.constructor "AVList"    Dhall.auto)
    <> (AVRecord  <$> Dhall.constructor "AVRecord"  Dhall.auto)
    <> (mkCompare <$> Dhall.constructor "AVCompare" cmpRecord)
    )
    where
      mkCompare (op, v) = AVCompare op v
      cmpRecord = Dhall.record $
        (,) <$> Dhall.field "op"    Dhall.auto
            <*> Dhall.field "value" Dhall.auto

-- | Generic Semantic AST element. The pair @(aKind, aPrimaryKey)@ is the
-- groupBy key the emitter uses to fold multiple state assertions for the same
-- resource into one @describe@ block.
--
-- @aAttrs@ comes from Dhall as @List { mapKey, mapValue }@ via 'toMap', so
-- duplicate keys cannot arise from the smart constructors. A user hand-writing
-- the underlying record could produce duplicates; 'Map.fromList' is
-- last-write-wins. Layer 3 (the emitter) catches unknown keys; silent merge of
-- duplicate keys is acceptable for Phase 1.
--
-- @aModule@ is an optional product label set by @Spec.module "name" […]@ in
-- the Dhall plan. The emitter partitions merged groups by this label so a
-- single host can produce multiple spec files (e.g. @Web/nginx_spec.rb@ and
-- @Web/php_spec.rb@). 'Nothing' means "no module label" — those assertions
-- land in the layout's default file. Module-aware splitting requires a v2
-- 'PanInfraSpec.Layout.Layout'; v1 layouts collapse all modules into one
-- file (which is the pre-module behaviour, byte-for-byte).
data Assertion = Assertion
  { aKind       :: Text
  , aPrimaryKey :: Text
  , aAttrs      :: Map Text AttrValue
  , aModule     :: Maybe Text
  }
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall Assertion where
  autoWith _ = Dhall.record $
    Assertion
      <$> Dhall.field "kind"       Dhall.auto
      <*> Dhall.field "primaryKey" Dhall.auto
      <*> Dhall.field "attrs"      Dhall.auto
      <*> Dhall.field "module"     Dhall.auto

-- | Binds a 'Selector' to the assertions that should apply to the matching
-- nodes. Lives here (rather than alongside 'Selector') because 'Mapping'
-- references 'Assertion' and 'PlanFile' references 'Mapping' — keeping them
-- co-located avoids a circular module dependency.
data Mapping = Mapping
  { mSelector   :: Selector
  , mAssertions :: [Assertion]
  }
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall Mapping where
  autoWith _ = Dhall.record $
    Mapping
      <$> Dhall.field "selector"   Dhall.auto
      <*> Dhall.field "assertions" Dhall.auto

-- | The whole loaded plan file. The @targetBackend@ field is forwarded from
-- the per-backend Dhall prelude (e.g., @Serverspec.dhall@) and lets the CLI
-- assert that @--target@ matches the prelude the user actually imported.
data PlanFile = PlanFile
  { pfTargetBackend :: Text
  , pfMappings      :: [Mapping]
  }
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall PlanFile where
  autoWith _ = Dhall.record $
    PlanFile
      <$> Dhall.field "targetBackend" Dhall.auto
      <*> Dhall.field "mappings"      Dhall.auto

-- | A node and the assertions resolved for it. Internal IR only; not loaded
-- from Dhall.
data Job = Job
  { jNode       :: Node
  , jAssertions :: [Assertion]
  }
  deriving stock (Show, Eq, Generic)

-- | The fully resolved plan handed to an emitter. @epTargetBackend@ drives
-- emitter dispatch.
data ExecutionPlan = ExecutionPlan
  { epTargetBackend :: Text
  , epJobs          :: [Job]
  }
  deriving stock (Show, Eq, Generic)
