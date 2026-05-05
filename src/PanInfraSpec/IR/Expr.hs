module PanInfraSpec.IR.Expr
  ( Operand (..)
  , Expr (..)
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)
import Numeric.Natural (Natural)

import qualified Dhall

-- | Leaf operand for the binary 'ExprAdd' / 'ExprSub' / 'ExprMul' /
-- 'ExprDiv' constructors. Stays flat (no nested 'Expr') because Dhall
-- lacks recursive types — composing more than two terms requires either
-- 'ExprFactIntScaled' (for the @fact * m1 * m2 ... \/ d@ shape) or the
-- 'PanInfraSpec.IR.ALRubyExpr' escape hatch.
data Operand
  = OpLit  Natural
    -- ^ Numeric literal.
  | OpFact Text
    -- ^ Reference to a host @customAttribute@ as
    --   @paninfraspec_\<name\>.to_i@. This is the "@Ref.Attr@" of the
    --   issue-#57 sketch.
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall Operand where
  autoWith _ = Dhall.union
    (  (OpLit  <$> Dhall.constructor "Lit"  Dhall.auto)
    <> (OpFact <$> Dhall.constructor "Fact" Dhall.auto)
    )

-- | Typed expression embedded inside an 'PanInfraSpec.IR.AttrLeaf' via
-- 'PanInfraSpec.IR.ALExpr'. Lets plans express recurring per-host
-- arithmetic patterns (e.g. \"70% of @paninfraspec_total_ram_kb@ in
-- bytes\", \"used = total - free\") without dropping into the opaque
-- 'PanInfraSpec.IR.ALRubyExpr' escape hatch.
--
-- Backend-agnostic: the renderer that turns these into Ruby/Bash/etc.
-- lives in each backend's emitter (see
-- 'PanInfraSpec.Emit.Serverspec.renderLeafRuby').
--
-- The constructor set is intentionally narrow ("first batches") and
-- grows additively as recurring escape-hatch patterns are observed in
-- the wild; see GitHub issue #57.
data Expr
  = ExprFactInt Text
    -- ^ Reference a host @customAttribute@ as @paninfraspec_\<name\>.to_i@.
  | ExprFactIntScaled Text [Natural] Natural
    -- ^ Reference a host @customAttribute@, multiply by zero or more
    --   'Natural' factors (left-to-right), then divide by the final
    --   'Natural'. Renders as
    --   @paninfraspec_\<name\>.to_i * m1 * m2 ... \/ divisor@. Empty
    --   factor lists are allowed (the result is just the integer
    --   division).
  | ExprAdd Operand Operand
    -- ^ Binary addition: @left + right@.
  | ExprSub Operand Operand
    -- ^ Binary subtraction: @left - right@.
  | ExprMul Operand Operand
    -- ^ Binary multiplication: @left * right@.
  | ExprDiv Operand Operand
    -- ^ Binary integer division: @left / right@. Divisor of @0@ is the
    --   user's responsibility (renders to Ruby that raises
    --   @ZeroDivisionError@ at spec run time).
  deriving stock (Show, Eq, Generic)

-- | The Dhall side declares
--
-- @
-- < FactInt       : Text
-- | FactIntScaled : { name : Text, muls : List Natural, divisor : Natural }
-- | Add           : { left : Operand, right : Operand }
-- | Sub           : { left : Operand, right : Operand }
-- | Mul           : { left : Operand, right : Operand }
-- | Div           : { left : Operand, right : Operand }
-- >
-- @
--
-- Dhall lacks recursive types, so the union stays flat at the leaf
-- level (the same constraint that keeps 'PanInfraSpec.IR.Selector'
-- boolean composition Haskell-only). Compose a third term by promoting
-- it to a separate 'Assertion' or by using 'ExprFactIntScaled' for the
-- @fact * literal * ... \/ literal@ shape.
instance Dhall.FromDhall Expr where
  autoWith _ = Dhall.union
    (  (ExprFactInt   <$> Dhall.constructor "FactInt"       Dhall.auto)
    <> (mkScaled      <$> Dhall.constructor "FactIntScaled" scaledRecord)
    <> (mkBin ExprAdd <$> Dhall.constructor "Add"           binRecord)
    <> (mkBin ExprSub <$> Dhall.constructor "Sub"           binRecord)
    <> (mkBin ExprMul <$> Dhall.constructor "Mul"           binRecord)
    <> (mkBin ExprDiv <$> Dhall.constructor "Div"           binRecord)
    )
    where
      mkScaled (n, ms, d) = ExprFactIntScaled n ms d
      mkBin con (l, r)    = con l r
      scaledRecord = Dhall.record $
        (,,) <$> Dhall.field "name"    Dhall.auto
             <*> Dhall.field "muls"    Dhall.auto
             <*> Dhall.field "divisor" Dhall.auto
      binRecord = Dhall.record $
        (,) <$> Dhall.field "left"  Dhall.auto
            <*> Dhall.field "right" Dhall.auto
