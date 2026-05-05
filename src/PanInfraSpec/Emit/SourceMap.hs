module PanInfraSpec.Emit.SourceMap
  ( EmitOptions (..)
  , defaultEmitOptions
  , formatSrcComment
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import PanInfraSpec.IR.SourceLoc (SourceLoc (..))

-- | Knobs threaded from the CLI down to each backend emitter.
--
-- 'sourceComments' controls whether @# src: <file>:<line>:<col> — <expr>@
-- provenance comments are prepended above each generated block. Disabled by
-- @--no-source-comments@ for users who want byte-stable output.
newtype EmitOptions = EmitOptions
  { sourceComments :: Bool
  }
  deriving stock (Show, Eq)

-- | Default: provenance comments on. Matches the CLI default so generated
-- specs are self-documenting out of the box.
defaultEmitOptions :: EmitOptions
defaultEmitOptions = EmitOptions { sourceComments = True }

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
