module PanInfraSpec.Emit.Backend
  ( Emitter
  , BackendEntry (..)
  ) where

import Data.Map.Strict (Map)
import Data.Text (Text)

import PanInfraSpec.IR (ExecutionPlan)
import PanInfraSpec.Layout (Layout)
import PanInfraSpec.Scaffold (Scaffold)

type Emitter = Scaffold -> Layout -> ExecutionPlan -> Either Text (Map FilePath Text)

data BackendEntry = BackendEntry
  { beEmitter      :: Emitter
  , beAllowedKinds :: [Text]
  }
