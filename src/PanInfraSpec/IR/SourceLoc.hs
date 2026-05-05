module PanInfraSpec.IR.SourceLoc
  ( SourceLoc (..)
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

-- | Where in a Dhall source file an IR node originated. Threaded through the
-- plan loader (see 'PanInfraSpec.Dhall.SourceMap') so emitters can prepend
-- @# src:@ provenance comments above each generated @describe@ block.
--
-- Lines and columns are 1-origin to match how editors and Dhall's
-- 'Dhall.Parser.SourcePos' report positions, so an operator can paste
-- @<file>:<line>:<col>@ into their editor and land on the responsible
-- expression.
data SourceLoc = SourceLoc
  { slFile      :: FilePath
  , slStartLine :: Int
  , slStartCol  :: Int
  , slEndLine   :: Int
  , slEndCol    :: Int
  , slText      :: Text
  }
  deriving stock (Show, Eq, Generic)
