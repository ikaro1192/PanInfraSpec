module PanInfraSpec.Layout
  ( Layout (..)
  , Sharing (..)
  , defaultLayout
  , loadLayout
  , validateLayoutPath
  , applySpecPath
  ) where

import Control.Exception (SomeException, try)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Dhall
import qualified System.FilePath.Posix as Posix
import qualified System.FilePath.Windows as Windows

import PanInfraSpec.IR (Node (..), nodeEncoder)

-- | How a layout maps inventory hosts onto output files.
--
-- 'PerHost' is the historic behaviour: every (node, module) pair must land
-- on a distinct path; 'emit' fails fast if 'lSpecPath' is not injective
-- across the inventory.
--
-- 'PerRole' acknowledges that a hostname-erased path
-- (e.g. @\<role\>/\<module\>_spec.rb@) is intended to be shared across
-- every host in the role. The emitter merges identical-content collisions
-- into a single output file. @customAttributes@ are allowed as long as
-- every host in the role declares the same set (matching @name@ and
-- @command@); the rendered preamble runs against each host's Specinfra
-- backend at runtime, so a role-shared file is correct. Divergent
-- customAttributes between hosts in the same role surface as a
-- differing-content error.
data Sharing = PerHost | PerRole
  deriving stock (Eq, Show)

instance Dhall.FromDhall Sharing where
  autoWith _ = Dhall.union
    (  (PerHost <$ Dhall.constructor "PerHost" Dhall.unit)
    <> (PerRole <$ Dhall.constructor "PerRole" Dhall.unit)
    )

-- | How output files are laid out under @--out DIR@.
--
-- 'lSpecPath' is the closure decoded from the user's Dhall function of
-- type @\\(n : Inventory.Node) -> \\(m : Optional Text) -> Text@. The
-- second argument carries the module label set via 'Spec.module_' in the
-- plan, so a single host can produce multiple spec files split by module
-- (e.g. @Web/nginx_spec.rb@ + @Web/php_spec.rb@). Layouts that do not care
-- about modules can ignore the argument.
--
-- 'lSharing' controls how the emitter resolves multiple jobs landing on
-- the same path; see 'Sharing'.
--
-- Auxiliary file paths (Rakefile, spec_helper.rb, ...) are owned by the
-- scaffold (see 'PanInfraSpec.Scaffold.sStaticFiles'), not by the layout.
data Layout = Layout
  { lSpecPath :: Node -> Maybe Text -> Text
  , lSharing  :: Sharing
  }

-- | The pre-Layout-feature behaviour: hostnames at the top of @--out@.
-- When a module label is set, it is appended to the filename so module
-- splits remain on disk distinct without forcing a custom layout.
defaultLayout :: Layout
defaultLayout = Layout
  { lSpecPath = \n m -> case m of
      Just label -> hostname n <> "_" <> label <> "_spec.rb"
      Nothing    -> hostname n <> "_spec.rb"
  , lSharing  = PerHost
  }

-- | Resolve the per-host (and optionally per-module) spec path. Forwards
-- both arguments to the user-supplied Dhall function.
applySpecPath :: Layout -> Node -> Maybe Text -> Text
applySpecPath layout = lSpecPath layout

-- | Decoder for the Layout shape:
-- @{ specPath : Node -> Optional Text -> Text, sharing : < PerHost | PerRole > }@.
decoder :: Dhall.Decoder Layout
decoder = Dhall.record $
  Layout
    <$> Dhall.field "specPath"
          (Dhall.function nodeEncoder
             (Dhall.function (Dhall.inject :: Dhall.Encoder (Maybe Text))
                Dhall.strictText))
    <*> Dhall.field "sharing" Dhall.auto

instance Dhall.FromDhall Layout where
  autoWith _ = decoder

-- | Load a Layout from a Dhall file.
loadLayout :: FilePath -> IO (Either Text Layout)
loadLayout path = do
  res <- try @SomeException (Dhall.inputFile decoder path)
  pure $ case res of
    Right l -> Right l
    Left  e -> Left (T.pack (show e))

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
