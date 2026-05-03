module PanInfraSpec.IR
  ( Role (..)
  , Node (..)
  , CompareOp (..)
  , AttrLeaf (..)
  , AttrValue (..)
  , Assertion (..)
  , Selector (..)
  , Mapping (..)
  , PlanFile (..)
  , Job (..)
  , ExecutionPlan (..)
  , roleEncoder
  , nodeEncoder
  ) where

import Data.Functor.Contravariant (contramap, (>$<))
import Data.Functor.Contravariant.Divisible (divided)
import Data.Map.Strict (Map)
import Data.String (IsString)
import Data.Text (Text)
import Numeric.Natural (Natural)
import GHC.Generics (Generic)

import qualified Dhall

-- | An organisation-defined role label. Kept as a Text wrapper because
-- vocabularies vary (Web / DBPrimary / cache / …).
newtype Role = Role { unRole :: Text }
  deriving stock   (Generic)
  deriving newtype (Show, Eq, Ord, IsString, Dhall.FromDhall)

-- | One inventory entry. Mirrors @dhall/Inventory.dhall@'s @Node@.
data Node = Node
  { hostname :: Text
  , ip       :: Maybe Text
  , role     :: Role
  , tags     :: [Text]
  }
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall Node where
  autoWith _ = Dhall.record $
    Node
      <$> Dhall.field "hostname" Dhall.auto
      <*> Dhall.field "ip"       Dhall.auto
      <*> Dhall.field "role"     Dhall.auto
      <*> Dhall.field "tags"     Dhall.auto

-- | Encoder for 'Role'. Wraps Text via the Role newtype unwrap. Needed so a
-- Dhall function value @\\(n : Inventory.Node) -> ...@ can be applied
-- host-by-host: dhall must inject the Haskell 'Node' back into a Dhall record
-- before evaluating the user's function. See 'PanInfraSpec.Layout'.
roleEncoder :: Dhall.Encoder Role
roleEncoder = contramap unRole Dhall.inject

-- | Encoder for 'Node'. The field set and types must match
-- @dhall/Inventory.dhall@'s @Node@ exactly, otherwise the user's
-- @\\(n : Inventory.Node) -> ...@ will not type-check at evaluation time.
--
-- 'Dhall.RecordEncoder' is not a 'Semigroup' in dhall-1.42, so we build the
-- record by composing field encoders through 'Divisible' ('divided') and
-- splaying 'Node' into a right-nested tuple.
nodeEncoder :: Dhall.Encoder Node
nodeEncoder = Dhall.recordEncoder $
  splay >$< (Dhall.encodeFieldWith "hostname" Dhall.inject
       `divided` (Dhall.encodeFieldWith "ip" Dhall.inject
       `divided` (Dhall.encodeFieldWith "role" roleEncoder
       `divided`  Dhall.encodeFieldWith "tags" Dhall.inject)))
  where
    splay n = (hostname n, (ip n, (role n, tags n)))

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
-- used for 'Selector' boolean composition).
data AttrLeaf
  = ALText   Text
  | ALNat    Natural
  | ALBool   Bool
  | ALSymbol Text
  | ALRegex  Text   -- ^ Ruby regex literal payload (without surrounding @/.../@).
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall AttrLeaf where
  autoWith _ = Dhall.union
    (  (ALText   <$> Dhall.constructor "ALText"   Dhall.auto)
    <> (ALNat    <$> Dhall.constructor "ALNat"    Dhall.auto)
    <> (ALBool   <$> Dhall.constructor "ALBool"   Dhall.auto)
    <> (ALSymbol <$> Dhall.constructor "ALSymbol" Dhall.auto)
    <> (ALRegex  <$> Dhall.constructor "ALRegex"  Dhall.auto)
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
data Assertion = Assertion
  { aKind       :: Text
  , aPrimaryKey :: Text
  , aAttrs      :: Map Text AttrValue
  }
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall Assertion where
  autoWith _ = Dhall.record $
    Assertion
      <$> Dhall.field "kind"       Dhall.auto
      <*> Dhall.field "primaryKey" Dhall.auto
      <*> Dhall.field "attrs"      Dhall.auto

-- | Selects which nodes a 'Mapping' applies to. AND/OR/NOT are added in
-- Phase 3 as additive constructors used for Haskell-side composition (e.g.,
-- CLI filter chaining). They have no Dhall surface because Dhall lacks
-- recursive types; the four base constructors below are the full set
-- reachable from a Dhall plan.
data Selector
  = SelAll
  | SelRole Role
  | SelTag  Text
  | SelHost Text
  | SelAnd  [Selector]
  | SelOr   [Selector]
  | SelNot  Selector
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall Selector where
  autoWith _ = Dhall.union
    (  (SelAll  <$  Dhall.constructor "SelAll"  Dhall.unit)
    <> (SelRole <$> Dhall.constructor "SelRole" Dhall.auto)
    <> (SelTag  <$> Dhall.constructor "SelTag"  Dhall.auto)
    <> (SelHost <$> Dhall.constructor "SelHost" Dhall.auto)
    -- AND / OR / NOT are not exposed via Dhall; Dhall lacks recursive types.
    -- Constructed Haskell-side only.
    )

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
-- assert that @--target@ matches the prelude the user actually imported
-- (specification.md §6.2).
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
