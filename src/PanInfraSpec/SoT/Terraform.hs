-- |
-- Terraform state JSON → 'Node' adapter.
--
-- Reads a @terraform.tfstate@ (schema v4) and produces an inventory by
-- walking every @resources[].instances[]@ whose @type@ is in
-- 'instanceTypes'. Tag conventions (Phase 4):
--
--   * @hostname@   ← @tags.Name@      (else @attributes.id@, else @<type>.<name>@)
--   * @ip@         ← @attributes.private_ip@ (else @public_ip@)
--   * @role@       ← @tags.Role@      (else @\"untagged\"@)
--   * @tags@       ← remaining tag values (Name and Role excluded)
--
-- Phase 4 ships @aws_instance@ only; other clouds (GCE / Azure VM) are a
-- straightforward extension to 'instanceTypes' plus per-type field
-- mappers in 'instanceToNode'.
module PanInfraSpec.SoT.Terraform
  ( TerraformStateFile (..)
  , TfState
  , parseTerraformStateFile
  , terraformToNodes
  ) where

import Control.Applicative ((<|>))
import Data.Aeson
  ( FromJSON (..)
  , Object
  , Value (Object, String)
  , eitherDecode
  , withObject
  , (.:)
  , (.:?)
  , (.!=)
  )
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)

import PanInfraSpec.IR (Node (..), Role (..))
import PanInfraSpec.SoT (SoT (..))

-- | Minimal subset of Terraform state v4 needed to produce an inventory.
newtype TfState = TfState { tfStateResources :: [TfResource] }
  deriving stock (Show, Eq)

instance FromJSON TfState where
  parseJSON = withObject "TfState" $ \v ->
    TfState <$> v .:? "resources" .!= []

data TfResource = TfResource
  { tfResType      :: Text
  , tfResName      :: Text
  , tfResInstances :: [TfInstance]
  }
  deriving stock (Show, Eq)

instance FromJSON TfResource where
  parseJSON = withObject "TfResource" $ \v -> TfResource
    <$> v .:  "type"
    <*> v .:  "name"
    <*> v .:? "instances" .!= []

newtype TfInstance = TfInstance { tfInstAttrs :: Object }
  deriving stock (Show, Eq)

instance FromJSON TfInstance where
  parseJSON = withObject "TfInstance" $ \v ->
    TfInstance <$> v .: "attributes"

-- | A path to a Terraform state JSON file. The 'SoT' instance reads and
-- decodes the file when 'toNodes' is called.
newtype TerraformStateFile = TerraformStateFile FilePath
  deriving stock (Show, Eq)

instance SoT TerraformStateFile where
  toNodes (TerraformStateFile path) =
    terraformToNodes <$> parseTerraformStateFile path

parseTerraformStateFile :: FilePath -> IO TfState
parseTerraformStateFile path = do
  bytes <- LBS.readFile path
  case eitherDecode bytes of
    Right s -> pure s
    Left e  -> fail ("terraform state parse failed (" <> path <> "): " <> e)

-- | Resource types treated as machine instances. Phase 4 covers AWS only.
instanceTypes :: [Text]
instanceTypes = ["aws_instance"]

terraformToNodes :: TfState -> [Node]
terraformToNodes (TfState resources) =
  concatMap nodesOf (filter wanted resources)
  where
    wanted r = tfResType r `elem` instanceTypes
    nodesOf r = mapMaybe (instanceToNode r) (tfResInstances r)

instanceToNode :: TfResource -> TfInstance -> Maybe Node
instanceToNode r (TfInstance attrs) = do
  let tagsMap = extractTags attrs
      mHost   = Map.lookup "Name" tagsMap
            <|> textField attrs "id"
            <|> Just (tfResType r <> "." <> tfResName r)
      mIp     = textField attrs "private_ip"
            <|> textField attrs "public_ip"
      roleT   = fromMaybe "untagged" (Map.lookup "Role" tagsMap)
      restTags =
        [ v
        | (k, v) <- Map.toAscList tagsMap
        , k /= "Name"
        , k /= "Role"
        ]
  hn <- mHost
  pure Node
    { hostname         = hn
    , ip               = mIp
    , role             = Role roleT
    , tags             = restTags
    , customAttributes = []
    }

-- | Read a Text-typed JSON attribute, returning 'Nothing' if missing or null.
textField :: Object -> Text -> Maybe Text
textField o key = case KM.lookup (Key.fromText key) o of
  Just (String s) -> Just s
  _               -> Nothing

-- | Extract @attributes.tags@ as a flat @Map Text Text@. Non-string values
-- are skipped silently — they're not meaningful for hostname/role mapping.
extractTags :: Object -> Map Text Text
extractTags attrs = case KM.lookup (Key.fromText "tags") attrs of
  Just (Object kv) ->
    Map.fromList
      [ (Key.toText k, v)
      | (k, String v) <- KM.toList kv
      ]
  _ -> Map.empty
