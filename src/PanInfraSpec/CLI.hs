module PanInfraSpec.CLI
  ( Options (..)
  , InventorySource (..)
  , parser
  , parserInfo
  , run
  , checkTargetMatches
  ) where

import Control.Exception (IOException, try)
import qualified Data.ByteString as BS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import Options.Applicative
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO (hPutStrLn, stderr)

import PanInfraSpec.Dhall (loadInventory, loadPlan, validate)
import PanInfraSpec.DumpPlan (dumpPlan)
import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Scaffold (Scaffold, defaultServerspecScaffold, loadScaffold)
import PanInfraSpec.IR
import PanInfraSpec.Layout (Layout, defaultLayout, loadLayout)
import PanInfraSpec.Resolve (matches, resolve)
import PanInfraSpec.SoT (toNodes)
import PanInfraSpec.SoT.Terraform (TerraformStateFile (..))

-- | Source of @[Node]@ data. The parser is built with @<|>@ so adding new
-- adapters in later phases stays additive.
--
-- The CLI flag for 'FromTerraformState' is @--from-terraform-state PATH@
-- (single token). An earlier @--from terraform-state PATH@ (two-token) form
-- was considered, but optparse-applicative's applicative parser cannot
-- dispatch on the value of a previously-parsed flag, so we collapse to a
-- single token. Each future adapter gets its own dedicated @--from-<adapter>@
-- flag.
data InventorySource
  = FromDhall          FilePath
  | FromTerraformState FilePath

data Options = Options
  { optInventory :: InventorySource
  , optPlan      :: FilePath
  , optTarget    :: Text
  , optOut       :: FilePath
  , optLayout    :: Maybe FilePath
  , optScaffold  :: Maybe FilePath
  , optOnlyRole  :: Maybe Text
  , optOnlyHost  :: Maybe Text
  , optOnlyTag   :: Maybe Text
  , optDumpPlan  :: Bool
  }

inventorySourceP :: Parser InventorySource
inventorySourceP = fromDhallP <|> fromTerraformP
  where
    fromDhallP = FromDhall <$> strOption
      ( long "inventory"
     <> metavar "PATH"
     <> help "Path to a Dhall inventory file (returns List Inventory.Node)"
      )
    fromTerraformP = FromTerraformState <$> strOption
      ( long "from-terraform-state"
     <> metavar "PATH"
     <> help "Path to a Terraform state JSON file; aws_instance resources \
             \become Nodes (mutex with --inventory)"
      )

parser :: Parser Options
parser = Options
  <$> inventorySourceP
  <*> strOption
        ( long "plan"
       <> metavar "PATH"
       <> help "Path to a Dhall plan file (returns List Plan.Mapping)"
        )
  <*> strOption
        ( long "target"
       <> metavar "BACKEND"
       <> help "Output backend (currently: serverspec)"
        )
  <*> strOption
        ( long "out"
       <> metavar "DIR"
       <> help "Output directory (created if missing)"
        )
  <*> optional (strOption
        ( long "layout"
       <> metavar "PATH"
       <> help "Path to a Dhall layout file (returns dhall/Layout.dhall's Layout). \
               \When omitted, files are written flat as <hostname>_spec.rb."
        ))
  <*> optional (strOption
        ( long "scaffold"
       <> metavar "PATH"
       <> help "Path to a Dhall scaffold file (returns dhall/Scaffold.dhall's Scaffold). \
               \When omitted, the built-in Serverspec scaffold is used."
        ))
  <*> optional (strOption
        ( long "only-role"
       <> metavar "ROLE"
       <> help "Restrict generation to nodes with this role"
        ))
  <*> optional (strOption
        ( long "only-host"
       <> metavar "HOST"
       <> help "Restrict generation to a single hostname"
        ))
  <*> optional (strOption
        ( long "only-tag"
       <> metavar "TAG"
       <> help "Restrict generation to nodes carrying this tag"
        ))
  <*> switch
        ( long "dump-plan"
       <> help "Print the resolved ExecutionPlan as a tree and exit (no output written)"
        )

parserInfo :: ParserInfo Options
parserInfo = info (parser <**> helper)
  ( fullDesc
 <> progDesc "Generate Serverspec specs from a Dhall inventory + plan"
 <> header   "paninfraspec-gen — multi-input / multi-output infra spec compiler"
  )

-- | Compose the active @--only-*@ flags into a single 'Selector' applied as
-- a node-level pre-filter. Multiple flags AND together (a node must match all
-- present clauses); no flags means 'SelAll'.
buildFilterSelector :: Options -> Selector
buildFilterSelector Options{..} = case clauses of
  []  -> SelAll
  [c] -> c
  cs  -> SelAnd cs
  where
    clauses = catMaybes
      [ SelRole . Role <$> optOnlyRole
      , SelHost        <$> optOnlyHost
      , SelTag         <$> optOnlyTag
      ]

filterNodes :: Options -> [Node] -> [Node]
filterNodes opts = filter (matches (buildFilterSelector opts))

-- | Load nodes from whichever 'InventorySource' the user selected.
loadNodes :: InventorySource -> IO (Either Text [Node])
loadNodes = \case
  FromDhall path          -> tryIO (loadInventory path)
  FromTerraformState path -> tryIO (toNodes (TerraformStateFile path))

-- | Resolve the active 'Layout': read the Dhall file when provided, else use
-- 'defaultLayout' so the pre-Layout-feature output stays bit-for-bit
-- identical when @--layout@ is omitted.
resolveLayout :: Maybe FilePath -> IO (Either Text Layout)
resolveLayout = \case
  Nothing   -> pure (Right defaultLayout)
  Just path -> do
    res <- tryIO (loadLayout path)
    pure $ case res of
      Left  e         -> Left e
      Right (Left e)  -> Left e
      Right (Right l) -> Right l

-- | Resolve the active 'Scaffold'. When the user did not pass @--scaffold@,
-- fall back to the built-in Serverspec scaffold.
resolveScaffold :: Maybe FilePath -> IO (Either Text Scaffold)
resolveScaffold Nothing = pure (Right defaultServerspecScaffold)
resolveScaffold (Just path) = do
  res <- tryIO (loadScaffold path)
  pure $ case res of
    Left  e         -> Left e
    Right (Left e)  -> Left e
    Right (Right s) -> Right s

-- | End-to-end pipeline. Returns 0 on success, 2 on any failure.
run :: Options -> IO ExitCode
run opts@Options{..} = do
  invRes <- loadNodes optInventory
  case invRes of
    Left e -> die ("inventory load failed: " <> e)
    Right nodes -> do
      planRes <- tryIO (loadPlan optPlan)
      case planRes of
        Left e -> die ("plan load failed: " <> e)
        Right pf -> case checkTargetMatches optTarget pf of
          Left e -> die e
          Right () ->
            let filtered = filterNodes opts nodes
                plan     = resolve optTarget filtered (pfMappings pf)
            in case validate plan of
                 Left e   -> die ("validation failed: " <> e)
                 Right ep
                   | optDumpPlan -> do
                       TIO.putStr (dumpPlan ep)
                       pure ExitSuccess
                   | otherwise -> do
                       layoutRes <- resolveLayout optLayout
                       case layoutRes of
                         Left e -> die ("layout load failed: " <> e)
                         Right layout -> do
                           scaffoldRes <- resolveScaffold optScaffold
                           case scaffoldRes of
                             Left e -> die ("scaffold load failed: " <> e)
                             Right scaffold -> case emitFor scaffold layout ep of
                               Left e     -> die ("emit failed: " <> e)
                               Right outs -> writeAll optOut outs

-- | Layer-1 check: the @--target@ flag must match the @targetBackend@ field
-- the plan file forwards from its imported per-backend Dhall prelude.
-- Returning @Left@ here is mapped to exit 2 by 'die'.
checkTargetMatches :: Text -> PlanFile -> Either Text ()
checkTargetMatches t pf
  | t == pfTargetBackend pf = Right ()
  | otherwise = Left $
      "target mismatch: --target=" <> t
      <> " but plan declares targetBackend=" <> pfTargetBackend pf

tryIO :: IO a -> IO (Either Text a)
tryIO io = do
  res <- try @IOException io
  case res of
    Right a -> pure (Right a)
    Left e  -> pure (Left (T.pack (show e)))

writeAll :: FilePath -> Map FilePath Text -> IO ExitCode
writeAll outDir files = do
  createDirectoryIfMissing True outDir
  res <- try @IOException $ mapM_ (uncurry write) (Map.toAscList files)
  case res of
    Right () -> pure ExitSuccess
    Left e   -> die ("write failed: " <> T.pack (show e))
  where
    -- The Layout API allows nested paths (e.g. "Web/web01_spec.rb"), so we
    -- have to materialise their parent directories before writing.
    write rel content = do
      let full = outDir </> rel
      createDirectoryIfMissing True (takeDirectory full)
      BS.writeFile full (TE.encodeUtf8 content)

die :: Text -> IO ExitCode
die msg = do
  hPutStrLn stderr ("paninfraspec-gen: " <> T.unpack msg)
  pure (ExitFailure 2)
