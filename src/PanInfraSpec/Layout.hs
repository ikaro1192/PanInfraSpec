module PanInfraSpec.Layout
  ( Layout (..)
  , defaultLayout
  , loadLayout
  , validateLayoutPath
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Dhall
import qualified System.FilePath.Posix as Posix
import qualified System.FilePath.Windows as Windows

import PanInfraSpec.IR (Node (..), nodeEncoder)

-- | How output files are laid out under @--out DIR@.
--
-- 'lSpecPath' is a Haskell closure decoded from the user's Dhall function
-- @\\(n : Inventory.Node) -> Text@. Re-applied once per 'Node' to get that
-- node's spec filename (relative to the output directory).
--
-- 'lHelperPath' / 'lRakefilePath' are static, validated at load time. They
-- have to remain in the same directory as the @*_spec.rb@ glob in the
-- generated Rakefile, but enforcing that would require parsing the user's
-- specPath function, so we leave it as a documented contract instead.
data Layout = Layout
  { lSpecPath     :: Node -> Text
  , lHelperPath   :: Text
  , lRakefilePath :: Text
  }

-- | The pre-Layout-feature behaviour: hostnames at the top of @--out@.
defaultLayout :: Layout
defaultLayout = Layout
  { lSpecPath     = \n -> hostname n <> "_spec.rb"
  , lHelperPath   = "spec_helper.rb"
  , lRakefilePath = "Rakefile"
  }

instance Dhall.FromDhall Layout where
  autoWith _ = Dhall.record $
    Layout
      <$> Dhall.field "specPath"     (Dhall.function nodeEncoder Dhall.strictText)
      <*> Dhall.field "helperPath"   Dhall.strictText
      <*> Dhall.field "rakefilePath" Dhall.strictText

-- | Load a Layout from a Dhall file. The static paths are validated here so
-- that errors surface before any node-spec emission.
loadLayout :: FilePath -> IO (Either Text Layout)
loadLayout path = do
  layout <- Dhall.inputFile Dhall.auto path
  pure $ do
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
