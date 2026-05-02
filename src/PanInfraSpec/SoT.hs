-- |
-- Source-of-Truth extension point. An 'SoT' instance produces a list of
-- 'Node's from some external system — Terraform state, kubectl, AWS SDK,
-- Netbox, Consul, etc. Phase 4 ships only the Terraform state instance
-- (see "PanInfraSpec.SoT.Terraform"); the typeclass exists so future
-- adapters drop in without touching the CLI plumbing or IR.
module PanInfraSpec.SoT
  ( SoT (..)
  ) where

import PanInfraSpec.IR (Node)

-- | Convert a configured adapter value into the Generic Semantic AST node
-- list. The 'IO' arises because most real adapters need to read a file, hit
-- an HTTP endpoint, or shell out — the typeclass leaves that scope open.
class SoT a where
  toNodes :: a -> IO [Node]
