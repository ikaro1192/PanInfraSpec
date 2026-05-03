module PanInfraSpec.Layout
  ( Layout (..)
  , defaultLayout
  , loadLayout
  , validateLayoutPath
  , applySpecPath
  , isLayoutV2
  ) where

import Control.Exception (SomeException, try)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Dhall
import qualified System.FilePath.Posix as Posix
import qualified System.FilePath.Windows as Windows

import PanInfraSpec.IR (Node (..), nodeEncoder)

-- | How output files are laid out under @--out DIR@.
--
-- 'lSpecPath' is the legacy v1 closure decoded from the user's Dhall
-- function @\\(n : Inventory.Node) -> Text@. It ignores any module label,
-- which keeps the pre-module behaviour byte-for-byte for users who haven't
-- adopted 'Spec.module_'.
--
-- 'lHelperPath' / 'lRakefilePath' are the v1 path overrides for the
-- well-known Serverspec auxiliary files. They control on-disk placement
-- only when the user did not pass @--scaffold@; an explicit @--scaffold@
-- means the scaffold's 'PanInfraSpec.Scaffold.sStaticFiles' paths win.
--
-- 'lSpecPathByModule' is the v2 closure decoded from a Dhall function of
-- type @\\(n : Inventory.Node) -> \\(m : Optional Text) -> Text@. When set,
-- it is used in preference to 'lSpecPath' and lets a single host produce
-- multiple spec files split by module label. v1 layouts leave this
-- 'Nothing'.
--
-- Why a single record with both shapes rather than a sum type: keeps every
-- existing call site (@layout { lSpecPath = ... }@ in tests, field
-- accessors elsewhere) compiling unchanged. The v2-vs-v1 distinction is
-- only checked in the few places that care: the emitter (via
-- 'applySpecPath') and the CLI (via 'isLayoutV2', so it knows whether to
-- patch scaffold paths from 'lHelperPath' / 'lRakefilePath').
data Layout = Layout
  { lSpecPath         :: Node -> Text
  , lHelperPath       :: Text
  , lRakefilePath     :: Text
  , lSpecPathByModule :: Maybe (Node -> Maybe Text -> Text)
  }

-- | The pre-Layout-feature behaviour: hostnames at the top of @--out@.
defaultLayout :: Layout
defaultLayout = Layout
  { lSpecPath         = \n -> hostname n <> "_spec.rb"
  , lHelperPath       = "spec_helper.rb"
  , lRakefilePath     = "Rakefile"
  , lSpecPathByModule = Nothing
  }

-- | True when the loaded layout uses the v2 @specPath@ signature
-- (@Node -> Optional Text -> Text@). v2 layouts do not carry
-- @helperPath@ / @rakefilePath@ — those paths come from the scaffold.
isLayoutV2 :: Layout -> Bool
isLayoutV2 layout = case lSpecPathByModule layout of
  Just _  -> True
  Nothing -> False

-- | Resolve the per-host (and optionally per-module) spec path. v1 layouts
-- ignore the module label (collapsing all modules into the same file —
-- the pre-module behaviour). v2 layouts forward both arguments to the
-- user-supplied Dhall function.
applySpecPath :: Layout -> Node -> Maybe Text -> Text
applySpecPath layout node maybeMod = case lSpecPathByModule layout of
  Just fn -> fn node maybeMod
  Nothing -> lSpecPath layout node

-- | Decoder for the v1 Layout shape:
-- @{ specPath : Node -> Text, helperPath : Text, rakefilePath : Text }@.
decoderV1 :: Dhall.Decoder Layout
decoderV1 = Dhall.record $
  (\sp h r -> Layout
                { lSpecPath         = sp
                , lHelperPath       = h
                , lRakefilePath     = r
                , lSpecPathByModule = Nothing
                })
    <$> Dhall.field "specPath"     (Dhall.function nodeEncoder Dhall.strictText)
    <*> Dhall.field "helperPath"   Dhall.strictText
    <*> Dhall.field "rakefilePath" Dhall.strictText

-- | Decoder for the v2 Layout shape:
-- @{ specPath : Node -> Optional Text -> Text }@. The result is stored in
-- 'lSpecPathByModule'; 'lSpecPath' is set to a wrapper that drops the
-- module label so any code path that has not yet been ported to
-- 'applySpecPath' still compiles and produces the no-module path.
decoderV2 :: Dhall.Decoder Layout
decoderV2 = Dhall.record $
  (\fn -> Layout
            { lSpecPath         = \n -> fn n Nothing
            , lHelperPath       = ""
            , lRakefilePath     = ""
            , lSpecPathByModule = Just fn
            })
    <$> Dhall.field "specPath"
          (Dhall.function nodeEncoder
             (Dhall.function (Dhall.inject :: Dhall.Encoder (Maybe Text))
                Dhall.strictText))

-- | The default 'FromDhall' instance picks v1 (most common shape today).
-- 'loadLayout' tries v2 first and falls back here, so external callers do
-- not depend on this default.
instance Dhall.FromDhall Layout where
  autoWith _ = decoderV1

-- | Load a Layout from a Dhall file. Tries the v2 shape first, falls back
-- to the v1 shape when that fails. Validates the v1 helper / Rakefile
-- paths so errors surface before any node-spec emission.
loadLayout :: FilePath -> IO (Either Text Layout)
loadLayout path = do
  v2Try <- try @SomeException (Dhall.inputFile decoderV2 path)
  case v2Try of
    Right l -> pure (validatePaths l)
    Left  _ -> do
      v1Try <- try @SomeException (Dhall.inputFile decoderV1 path)
      case v1Try of
        Right l -> pure (validatePaths l)
        Left  e -> pure (Left (T.pack (show e)))
  where
    validatePaths layout
      | isLayoutV2 layout = Right layout
      | otherwise         = do
          _ <- validateLayoutPath (T.unpack (lHelperPath   layout))
          _ <- validateLayoutPath (T.unpack (lRakefilePath layout))
          Right layout

-- | Reject paths that would escape the output directory or alias the host
-- filesystem. Empty, absolute, traversing (@..@), and control-character paths
-- are all rejected.
--
-- 'System.FilePath.isAbsolute' is host-platform-specific: on Windows it
-- returns 'False' for @\/etc\/passwd@ because there is no drive letter, while
-- on POSIX it returns 'False' for @C:\\foo@. To make the validation behave the
-- same on every CI runner we evaluate /both/ the POSIX and Windows rules and
-- also reject any path that simply begins with a separator (@\\foo@ alone has
-- no drive letter on Windows but still escapes 'outDir').
validateLayoutPath :: FilePath -> Either Text FilePath
validateLayoutPath p
  | null p              = Left "layout path is empty"
  | hasLeadingSep p
  || Posix.isAbsolute p
  || Windows.isAbsolute p
                        = Left ("absolute paths are not allowed in layout: " <> T.pack p)
  -- Windows.splitDirectories splits on both @/@ and @\\@, so it surfaces a
  -- traversal regardless of which separator the user wrote.
  | any (== "..") (Windows.splitDirectories p)
                        = Left ("layout path escapes the output directory: " <> T.pack p)
  | T.any forbidden (T.pack p)
                        = Left ("layout path contains forbidden characters: " <> T.pack p)
  | otherwise           = Right p
  where
    hasLeadingSep ('/':_)  = True
    hasLeadingSep ('\\':_) = True
    hasLeadingSep _        = False
    forbidden c = c == '\NUL' || c == '\n' || c == '\r'
