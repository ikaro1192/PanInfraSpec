-- | Cross-backend registry of allowed @aKind@ values. Each emitter
-- contributes its own entry, and the layer-2 validator in
-- 'PanInfraSpec.Dhall' looks up the per-backend allowlist here instead of
-- pattern-matching on backend names. Adding a new backend requires only a
-- new module plus one entry in this map.
module PanInfraSpec.Emit.Registry
  ( backendRegistry
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

import qualified PanInfraSpec.Emit.Serverspec as Serverspec

backendRegistry :: Map Text [Text]
backendRegistry = Map.fromList
  [ ("serverspec", Serverspec.serverspecAllowedKinds)
  ]
