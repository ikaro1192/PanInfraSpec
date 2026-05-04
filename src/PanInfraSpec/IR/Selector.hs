module PanInfraSpec.IR.Selector
  ( Selector (..)
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

import qualified Dhall

import PanInfraSpec.IR.Inventory (Role)

-- | Selects which nodes a 'PanInfraSpec.IR.Assertion.Mapping' applies to.
-- AND/OR/NOT are added in Phase 3 as additive constructors used for
-- Haskell-side composition (e.g., CLI filter chaining). They have no Dhall
-- surface because Dhall lacks recursive types; the four base constructors
-- below are the full set reachable from a Dhall plan.
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
