module PanInfraSpec.Resolve
  ( matches
  , resolve
  ) where

import Data.Text (Text)

import PanInfraSpec.IR

-- | Does a single 'Selector' apply to the given 'Node'?
matches :: Selector -> Node -> Bool
matches SelAll       _ = True
matches (SelRole r)  n = role n == r
matches (SelTag t)   n = t `elem` tags n
matches (SelHost h)  n = hostname n == h
matches (SelAnd ss)  n = all (`matches` n) ss
matches (SelOr ss)   n = any (`matches` n) ss
matches (SelNot s)   n = not (matches s n)

-- | Build an 'ExecutionPlan' for the given backend by applying every
-- 'Mapping' to every 'Node'. Nodes that match zero mappings are dropped.
resolve :: Text -> [Node] -> [Mapping] -> ExecutionPlan
resolve backend nodes ms = ExecutionPlan
  { epTargetBackend = backend
  , epJobs =
      [ Job n (concatMap mAssertions matched)
      | n <- nodes
      , let matched = filter (\m -> matches (mSelector m) n) ms
      , not (null matched)
      ]
  }
