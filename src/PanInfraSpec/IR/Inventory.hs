module PanInfraSpec.IR.Inventory
  ( Role (..)
  , CustomAttribute (..)
  , Node (..)
  , roleEncoder
  , customAttributeEncoder
  , nodeEncoder
  ) where

import Data.Functor.Contravariant (contramap, (>$<))
import Data.Functor.Contravariant.Divisible (divided)
import Data.String (IsString)
import Data.Text (Text)
import GHC.Generics (Generic)

import qualified Dhall

-- | An organisation-defined role label. Kept as a Text wrapper because
-- vocabularies vary (Web / DBPrimary / cache / …).
newtype Role = Role { unRole :: Text }
  deriving stock   (Generic)
  deriving newtype (Show, Eq, Ord, IsString, Dhall.FromDhall)

-- | A per-host shell command whose stdout becomes a Ruby variable bound at
-- the top of the generated spec file (as @paninfraspec_<caName>@). Plans can
-- then reference that value via 'AttrLeaf.ALRubyExpr', enabling
-- host-dependent expected values (e.g., "innodb_buffer_pool_size must be at
-- least 70% of the host's total RAM"). Mirrors the Dhall record
-- @{ name : Text, command : Text }@ in @dhall/Inventory.dhall@.
data CustomAttribute = CustomAttribute
  { caName    :: Text
  , caCommand :: Text
  }
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall CustomAttribute where
  autoWith _ = Dhall.record $
    CustomAttribute
      <$> Dhall.field "name"    Dhall.auto
      <*> Dhall.field "command" Dhall.auto

-- | One inventory entry. Mirrors @dhall/Inventory.dhall@'s @Node@.
data Node = Node
  { hostname         :: Text
  , ip               :: Maybe Text
  , role             :: Role
  , tags             :: [Text]
  , customAttributes :: [CustomAttribute]
  }
  deriving stock (Show, Eq, Generic)

instance Dhall.FromDhall Node where
  autoWith _ = Dhall.record $
    Node
      <$> Dhall.field "hostname"         Dhall.auto
      <*> Dhall.field "ip"               Dhall.auto
      <*> Dhall.field "role"             Dhall.auto
      <*> Dhall.field "tags"             Dhall.auto
      <*> Dhall.field "customAttributes" Dhall.auto

-- | Encoder for 'Role'. Wraps Text via the Role newtype unwrap. Needed so a
-- Dhall function value @\\(n : Inventory.Node) -> ...@ can be applied
-- host-by-host: dhall must inject the Haskell 'Node' back into a Dhall record
-- before evaluating the user's function. See 'PanInfraSpec.Layout'.
roleEncoder :: Dhall.Encoder Role
roleEncoder = contramap unRole Dhall.inject

-- | Encoder for 'CustomAttribute'. Mirrors the Dhall record
-- @{ name : Text, command : Text }@ so a user-written
-- @\\(n : Inventory.Node) -> ...@ can reach @n.customAttributes@ during
-- Layout evaluation if it ever wants to.
customAttributeEncoder :: Dhall.Encoder CustomAttribute
customAttributeEncoder = Dhall.recordEncoder $
  splay >$< (Dhall.encodeFieldWith "name"    Dhall.inject
       `divided`  Dhall.encodeFieldWith "command" Dhall.inject)
  where
    splay c = (caName c, caCommand c)

-- | 'ToDhall' instance for 'CustomAttribute' lets @Dhall.inject@ derive an
-- encoder for @[CustomAttribute]@ when building 'nodeEncoder'.
instance Dhall.ToDhall CustomAttribute where
  injectWith _ = customAttributeEncoder

-- | 'ToDhall' instance for 'Node' lets @Dhall.inject@ derive an encoder for
-- @[Node]@. Needed by 'PanInfraSpec.Scaffold' so a Dhall function value
-- @\\(nodes : List Inventory.Node) -> ...@ can be applied to the resolved
-- inventory at emit time.
instance Dhall.ToDhall Node where
  injectWith _ = nodeEncoder

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
       `divided` (Dhall.encodeFieldWith "tags" Dhall.inject
       `divided`  Dhall.encodeFieldWith "customAttributes" Dhall.inject))))
  where
    splay n = (hostname n, (ip n, (role n, (tags n, customAttributes n))))
