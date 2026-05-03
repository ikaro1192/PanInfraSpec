module PanInfraSpec.Layout
  ( Layout (..)
  , defaultLayout
  , loadLayout
  , validateLayoutPath
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Dhall
import System.FilePath (isAbsolute, splitDirectories)

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
-- We deliberately do not reject Windows drive letters explicitly: 'isAbsolute'
-- on Windows already covers @C:\\@; on POSIX a string like @"C:foo"@ is just a
-- relative path with a colon, which Serverspec users do not produce in
-- practice.
validateLayoutPath :: FilePath -> Either Text FilePath
validateLayoutPath p
  | null p                            = Left "layout path is empty"
  | isAbsolute p                      = Left ("absolute paths are not allowed in layout: " <> T.pack p)
  | any (== "..") (splitDirectories p) = Left ("layout path escapes the output directory: " <> T.pack p)
  | T.any forbidden (T.pack p)        = Left ("layout path contains forbidden characters: " <> T.pack p)
  | otherwise                         = Right p
  where
    forbidden c = c == '\NUL' || c == '\n' || c == '\r'
