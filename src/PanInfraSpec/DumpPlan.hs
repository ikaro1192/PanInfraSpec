module PanInfraSpec.DumpPlan
  ( dumpPlan
  ) where

import Data.Function (on)
import Data.List (groupBy, sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

import PanInfraSpec.IR

-- | Render an 'ExecutionPlan' as a human-readable tree. Pre-groups assertions
-- by @(aKind, aPrimaryKey)@ so the output mirrors the @describe@-block
-- structure that the emitter would actually produce — useful when debugging
-- selector resolution and merge behavior.
dumpPlan :: ExecutionPlan -> Text
dumpPlan ep =
  let header  = "ExecutionPlan (target=" <> epTargetBackend ep
             <> ", jobs=" <> tshow (length (epJobs ep)) <> ")"
      body    = T.unlines (concatMap renderJob (epJobs ep))
  in T.unlines [header] <> body

renderJob :: Job -> [Text]
renderJob (Job n assertions) =
  let host    = "├── " <> hostname n
             <> "  role=" <> unRole (role n)
             <> "  tags=" <> renderTags (tags n)
             <> renderIp (ip n)
      grouped = groupAssertions assertions
      lines_  = map (renderGroup . mergeGroupSimple) grouped
  in host : lines_

renderTags :: [Text] -> Text
renderTags ts = "[" <> T.intercalate "," ts <> "]"

renderIp :: Maybe Text -> Text
renderIp = \case
  Nothing  -> ""
  Just a   -> "  ip=" <> a

renderGroup :: Assertion -> Text
renderGroup (Assertion k pk attrs _) =
  "│   ├── " <> k <> " " <> quoted pk <> " " <> renderAttrs attrs

renderAttrs :: Map.Map Text AttrValue -> Text
renderAttrs m =
  "{" <> T.intercalate ", " [ key <> "=" <> renderValue v | (key, v) <- Map.toAscList m ] <> "}"

renderValue :: AttrValue -> Text
renderValue = \case
  AVText    t   -> "\"" <> t <> "\""
  AVNat     n   -> tshow n
  AVBool    b   -> if b then "True" else "False"
  AVSymbol  s   -> ":" <> s
  AVList    xs  -> "[" <> T.intercalate ", " (map renderLeaf xs) <> "]"
  AVRecord  m   -> "{" <> T.intercalate ", "
                     [ k <> "=" <> renderLeaf v | (k, v) <- Map.toAscList m ]
                <> "}"
  AVCompare o v -> renderOp o <> " " <> renderLeaf v

renderLeaf :: AttrLeaf -> Text
renderLeaf = \case
  ALText     t -> "\"" <> t <> "\""
  ALNat      n -> tshow n
  ALBool     b -> if b then "True" else "False"
  ALSymbol   s -> ":" <> s
  ALRegex    p -> "/" <> p <> "/"
  ALRubyExpr e -> "{ruby:" <> e <> "}"

renderOp :: CompareOp -> Text
renderOp = \case
  OpLt    -> "<"
  OpLe    -> "<="
  OpGt    -> ">"
  OpGe    -> ">="
  OpEq    -> "=="
  OpMatch -> "=~"

quoted :: Text -> Text
quoted t = "\"" <> t <> "\""

tshow :: Show a => a -> Text
tshow = T.pack . show

-- | Pre-group by @(kind, primaryKey)@ in stable order — does NOT enforce
-- conflict detection (that's the emitter's job). Duplicate or conflicting
-- attrs collapse via Map.union (last-write-wins) for display purposes.
groupAssertions :: [Assertion] -> [NonEmpty Assertion]
groupAssertions = map NE.fromList
                . groupBy ((==) `on` key)
                . sortOn key
  where
    key a = (aKind a, aPrimaryKey a)

mergeGroupSimple :: NonEmpty Assertion -> Assertion
mergeGroupSimple (a :| rest) = a { aAttrs = foldr (Map.union . aAttrs) (aAttrs a) rest }
