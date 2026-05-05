module PanInfraSpec.Emit.SourceMap
  ( EmitOptions (..)
  , defaultEmitOptions
  , formatSrcComment
  , formatDescribeSrcLoc
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import PanInfraSpec.IR.SourceLoc (SourceLoc (..))

-- | Knobs threaded from the CLI down to each backend emitter.
--
-- 'sourceComments' controls whether @# src: <file>:<line>:<col> — <expr>@
-- provenance comments are prepended above each generated block. Disabled by
-- @--no-source-comments@ for users who want byte-stable output.
--
-- 'sourceLocInDescribe' controls whether the Dhall source location is also
-- woven into each @describe@ block's secondary description string, so RSpec
-- runtime output (e.g. @rake spec@) prints the originating plan line next to
-- the resource name. Off by default because it changes the human-readable
-- test output that downstream CI tooling may parse; users opt in with
-- @--source-loc-in-describe@.
data EmitOptions = EmitOptions
  { sourceComments      :: Bool
  , sourceLocInDescribe :: Bool
  }
  deriving stock (Show, Eq)

-- | Default: provenance comments on, runtime describe-string off. The first
-- matches the CLI default so generated specs are self-documenting out of the
-- box; the second stays opt-in to avoid silently changing @rake spec@ output.
defaultEmitOptions :: EmitOptions
defaultEmitOptions = EmitOptions
  { sourceComments      = True
  , sourceLocInDescribe = False
  }

-- | Render one @# src:@ line per 'SourceLoc'. Empty input yields no lines so
-- callers can splice the result unconditionally with 'vsep'.
--
-- Each Dhall expression is collapsed to a single line (multi-line expressions
-- are joined with single spaces) and truncated past 'maxOneLineLen' so a
-- pathologically long expression cannot blow up the generated file. Truncation
-- appends a U+2026 ellipsis so readers can tell the comment was clipped.
formatSrcComment :: [SourceLoc] -> [Text]
formatSrcComment = map renderOne
  where
    renderOne loc =
      "# src: "
        <> T.pack (slFile loc)
        <> ":"
        <> T.pack (show (slStartLine loc))
        <> ":"
        <> T.pack (show (slStartCol loc))
        <> " — "
        <> oneLine (slText loc)

    oneLine t =
      let collapsed = T.unwords (T.words t)
      in if T.length collapsed > maxOneLineLen
           then T.take (maxOneLineLen - 1) collapsed <> "…"
           else collapsed

    maxOneLineLen :: Int
    maxOneLineLen = 80

-- | Render a single secondary-description string suitable for RSpec's
-- @describe <subject>, '<string>' do@ form. Returns 'Nothing' when there are
-- no source locations so callers can omit the secondary argument entirely
-- (the produced string is never empty otherwise).
--
-- Each location collapses to @file:line:col@ — the raw expression text is
-- intentionally dropped. RSpec prints the secondary string inline with the
-- resource name on the same line, so verbosity matters more than for the
-- multi-line @# src:@ comment form.
formatDescribeSrcLoc :: [SourceLoc] -> Maybe Text
formatDescribeSrcLoc [] = Nothing
formatDescribeSrcLoc locs =
  Just ("(" <> T.intercalate ", " (map renderOne locs) <> ")")
  where
    renderOne loc =
      T.pack (slFile loc)
        <> ":"
        <> T.pack (show (slStartLine loc))
        <> ":"
        <> T.pack (show (slStartCol loc))
