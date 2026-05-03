module PanInfraSpec.Emit
  ( emitFor
  ) where

import Data.Map.Strict (Map)
import Data.Text (Text)

import PanInfraSpec.Scaffold (Scaffold)
import PanInfraSpec.IR
import PanInfraSpec.Layout (Layout)
import qualified PanInfraSpec.Emit.Serverspec as Serverspec

-- | Dispatch on 'epTargetBackend'. The chosen emitter performs its own
-- backend guard at the top of its 'emit', so a misrouted call still produces
-- an explicit error rather than silently mis-formatting.
--
-- The 'Scaffold' argument supplies the runner-specific files (Rakefile /
-- spec_helper.rb / inventory-derived auxiliaries). 'Layout' still owns
-- per-host spec-file paths.
emitFor :: Scaffold -> Layout -> ExecutionPlan -> Either Text (Map FilePath Text)
emitFor scaffold layout ep = case epTargetBackend ep of
  "serverspec" -> Serverspec.emit scaffold layout ep
  b            -> Left ("unknown backend: " <> b)
