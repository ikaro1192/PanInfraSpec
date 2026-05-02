module PanInfraSpec.Emit
  ( emitFor
  ) where

import Data.Map.Strict (Map)
import Data.Text (Text)

import PanInfraSpec.IR
import qualified PanInfraSpec.Emit.Serverspec as Serverspec

-- | Dispatch on 'epTargetBackend'. The chosen emitter performs its own
-- backend guard at the top of its 'emit', so a misrouted call still produces
-- an explicit error rather than silently mis-formatting.
emitFor :: ExecutionPlan -> Either Text (Map FilePath Text)
emitFor ep = case epTargetBackend ep of
  "serverspec" -> Serverspec.emit ep
  b            -> Left ("unknown backend: " <> b)
