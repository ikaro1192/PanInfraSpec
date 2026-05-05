module PanInfraSpec.Emit
  ( emitFor
  , knownBackends
  , backendAllowedKinds
  , registry
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

import PanInfraSpec.Emit.Backend (BackendEntry (..))
import PanInfraSpec.Emit.SourceMap (EmitOptions)
import qualified PanInfraSpec.Emit.Serverspec as Serverspec
import PanInfraSpec.IR
import PanInfraSpec.Layout (Layout)
import PanInfraSpec.Scaffold (Scaffold)

-- | Single source of truth for which backends this build knows about. Adding a
-- new backend is one new import and one new entry in this map; no other
-- dispatcher edits are required.
registry :: Map Text BackendEntry
registry = Map.fromList
  [ ("serverspec", Serverspec.serverspecBackend)
  ]

-- | Backends recognised by this build, derived from 'registry'.
knownBackends :: [Text]
knownBackends = Map.keys registry

-- | Allowed @aKind@ values per backend, derived from 'registry'. Returns @[]@
-- for backend names not present in the registry; 'PanInfraSpec.Dhall.validate'
-- relies on this so an unknown backend rejects every assertion at layer 2.
backendAllowedKinds :: Text -> [Text]
backendAllowedKinds name =
  maybe [] beAllowedKinds (Map.lookup name registry)

-- | Dispatch on 'epTargetBackend' via the registry. The 'Scaffold' argument
-- supplies the runner-specific files (Rakefile / spec_helper.rb /
-- inventory-derived auxiliaries); 'Layout' still owns per-host spec-file paths.
-- Misrouted backend calls return the historical @"unknown backend: <name>"@
-- error message so callers (and tests) can match on it.
emitFor
  :: Scaffold
  -> Layout
  -> ExecutionPlan
  -> EmitOptions
  -> Either Text (Map FilePath Text)
emitFor scaffold layout ep opts =
  case Map.lookup (epTargetBackend ep) registry of
    Just entry -> beEmitter entry scaffold layout ep opts
    Nothing    -> Left ("unknown backend: " <> epTargetBackend ep)
