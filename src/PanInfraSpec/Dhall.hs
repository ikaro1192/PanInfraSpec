module PanInfraSpec.Dhall
  ( loadInventory
  , loadPlan
  , validate
  , backendAllowedKinds
  , knownBackends
  ) where

import Control.Exception (throwIO)
import qualified Control.Monad.Trans.State.Strict as State
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Dhall
import qualified Dhall.Core as DC
import qualified Dhall.Import as DImport
import qualified Dhall.Marshal.Decode as DDecode
import qualified Dhall.TypeCheck as DTypeCheck
import qualified Dhall.Parser as DParser
import System.FilePath (takeDirectory)

import PanInfraSpec.Dhall.SourceMap (attachLocs, extractAssertionLocs)
import PanInfraSpec.Emit (backendAllowedKinds, knownBackends)
import PanInfraSpec.IR

-- | Load the inventory file via Dhall and decode to @[Node]@.
loadInventory :: FilePath -> IO [Node]
loadInventory = Dhall.inputFile Dhall.auto

-- | Load the plan file and decode to a 'PlanFile'. We bypass
-- 'Dhall.inputFile' so we can run an AST walker over the resolved-but-still
-- annotated tree, capturing each assertion's 'SourceLoc' before
-- normalisation strips the @Note s@ wrappers. The decoded value goes through
-- 'Dhall.input' as before; 'attachLocs' splices the captured locations back
-- in by their declaration index.
--
-- The walker only finds locations when the plan's outermost expression is a
-- record literal containing a @mappings@ list — i.e. the plan is written as
-- @{ targetBackend = ..., mappings = [...] }@ rather than going through
-- @Plan.make@'s lambda (which would be β-reduced and thus lose all
-- 'Note' wrappers). Plans authored against the older smart-constructor
-- shape still load; they simply produce no @# src:@ comments because no
-- locations were captured.
loadPlan :: FilePath -> IO PlanFile
loadPlan path = do
  raw      <- TIO.readFile path
  parsed   <- case DParser.exprFromText path raw of
    Left  e -> throwIO e
    Right e -> pure e
  resolved <- State.evalStateT
                (DImport.loadWith parsed)
                (DImport.emptyStatus (takeDirectory path))
  case DTypeCheck.typeOf resolved of
    Left  e -> throwIO e
    Right _ -> pure ()
  let locs       = extractAssertionLocs path resolved
      normalized = DC.normalize resolved
  pf <- case DDecode.toMonadic (Dhall.extract Dhall.auto normalized) of
    Right a   -> pure a
    Left errs -> throwIO errs
  pure (attachLocs locs pf)

-- | Layer-2 validation: structural integrity + backend kind allowlist.
-- Layer 3 (attrs schema, conflict fail-safe) is the emitter's responsibility.
validate :: ExecutionPlan -> Either Text ExecutionPlan
validate ep
  | T.null (epTargetBackend ep) =
      Left "empty targetBackend"
  | epTargetBackend ep `notElem` knownBackends =
      Left ("unknown backend: " <> epTargetBackend ep)
  | Just bad <- find badAssertion allAs =
      Left ("empty kind or primaryKey at: " <> aPrimaryKey bad)
  | Just bad <- find unknownKind allAs =
      Left ("kind not allowed for backend " <> epTargetBackend ep <> ": " <> aKind bad)
  | otherwise = Right ep
  where
    allAs        = concatMap jAssertions (epJobs ep)
    allowed      = backendAllowedKinds (epTargetBackend ep)
    badAssertion a = T.null (aKind a) || T.null (aPrimaryKey a)
    unknownKind  a = aKind a `notElem` allowed
