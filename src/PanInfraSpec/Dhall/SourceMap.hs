module PanInfraSpec.Dhall.SourceMap
  ( extractAssertionLocs
  , attachLocs
  , betaReduceKeepNotes
  ) where

import qualified Data.Foldable as F
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (maybeToList)
import Data.Void (Void)

import qualified Dhall.Core as DC
import qualified Dhall.Map  as DMap
import Dhall.Src (Src (..))
import qualified Text.Megaparsec.Pos as Pos

import PanInfraSpec.IR
  ( Assertion (..)
  , Mapping (..)
  , PlanFile (..)
  )
import PanInfraSpec.IR.SourceLoc (SourceLoc (..))

-- | Walk the resolved Plan AST and produce, for every assertion a Plan can
-- contain, the 'SourceLoc' that wraps it in the original Dhall file.
--
-- The walker indexes each assertion by @(mappingIdx, assertionIdx)@ in
-- declaration order; 'attachLocs' uses the same index pair to splice the
-- locations back into the corresponding 'Assertion' values after Dhall has
-- finished decoding the value side.
--
-- This must run before normalisation. 'Dhall.Core.normalize' rewrites
-- @Note s e@ to @e@, and that throws away everything we need. The plan
-- pipeline therefore typechecks the resolved AST, runs this walker, and only
-- then hands a normalised copy to 'Dhall.input' for value extraction.
extractAssertionLocs
  :: FilePath
  -> DC.Expr Src Void
  -> Map (Int, Int) SourceLoc
extractAssertionLocs path expr = case stripWrappers (betaReduceKeepNotes expr) of
  DC.RecordLit fields ->
    maybe Map.empty (walkMappings . DC.recordFieldValue) (DMap.lookup "mappings" fields)
  _ -> Map.empty
  where
    walkMappings e = case stripWrappers e of
      DC.ListLit _ items ->
        Map.unions
          [ walkMapping mIdx item
          | (mIdx, item) <- zip [0 ..] (F.toList items)
          ]
      _ -> Map.empty

    walkMapping mIdx e = case stripWrappers e of
      DC.RecordLit fields ->
        maybe
          Map.empty
          (walkAssertions mIdx . DC.recordFieldValue)
          (DMap.lookup "assertions" fields)
      _ -> Map.empty

    walkAssertions mIdx e = case stripWrappers e of
      DC.ListLit _ items ->
        Map.fromList
          [ ((mIdx, aIdx), srcToLoc path src)
          | (aIdx, item) <- zip [0 ..] (F.toList items)
          , src           <- maybeToList (outermostSrc item)
          ]
      _ -> Map.empty

-- | Peel away purely structural wrappers — 'Note' annotations introduced by
-- the parser, 'Let' bindings introduced by @let X = ... in ...@, and type
-- 'Annot' annotations — to find the underlying record/list literal a writer
-- intends. We resolve imports before reaching this walker, so any @let@ that
-- bound an import (e.g. @let Spec = ./Serverspec.dhall@) is just a let
-- holding a record literal whose body still references @Spec@; descending
-- into the @in ...@ side and ignoring the binder is what we want, since the
-- mapping/assertion structure we care about lives in the body.
stripWrappers :: DC.Expr Src a -> DC.Expr Src a
stripWrappers (DC.Note _ e)  = stripWrappers e
stripWrappers (DC.Let _ e)   = stripWrappers e
stripWrappers (DC.Annot e _) = stripWrappers e
stripWrappers e              = e

-- | The outermost 'Src' that wraps an expression, if any. Dhall sometimes
-- produces nested 'Note' constructors; we want the widest range so the
-- emitted comment shows the entire @file_owner "/x" "y"@ application rather
-- than just the head identifier.
outermostSrc :: DC.Expr Src a -> Maybe Src
outermostSrc (DC.Note s _) = Just s
outermostSrc _             = Nothing

srcToLoc :: FilePath -> Src -> SourceLoc
srcToLoc path src = SourceLoc
  { slFile      = path
  , slStartLine = Pos.unPos (Pos.sourceLine   (srcStart src))
  , slStartCol  = Pos.unPos (Pos.sourceColumn (srcStart src))
  , slEndLine   = Pos.unPos (Pos.sourceLine   (srcEnd   src))
  , slEndCol    = Pos.unPos (Pos.sourceColumn (srcEnd   src))
  , slText      = srcText src
  }

-- | Partial normaliser that performs β-reduction, let-inlining, and
-- record-field projection while leaving every 'DC.Note' wrapper in place.
--
-- 'Dhall.Core.normalize' would do all of the same reductions and more, but
-- it discards 'Note' annotations along the way — and those are exactly what
-- the source-map walker needs. By driving the reductions ourselves we can
-- preserve every 'Note' that ends up surviving in the head-normal form, so
-- a plan that goes through smart constructors like 'Plan.forRole' still
-- exposes each assertion's location to the walker.
--
-- This intentionally implements only the subset Dhall needs to evaluate the
-- @Plan.dhall@ / @Serverspec.dhall@ smart-constructor library: lambda
-- application, top-level @let@ inlining, and field projection on record
-- literals. Other reductions (booleans, list folds, type-level rewrites,
-- @merge@, …) are left as-is — they do not appear in plan files in
-- practice, and supporting them would risk drifting out of sync with
-- dhall's own normaliser.
betaReduceKeepNotes :: DC.Expr Src a -> DC.Expr Src a
betaReduceKeepNotes = go
  where
    go expr = case expr of
      DC.Note s e -> DC.Note s (go e)

      DC.App f x ->
        let f' = go f
            x' = go x
            spineHead = collectAppHead f'
            spineArgs = collectAppArgs f' ++ [x']
        in case peelOuter spineHead of
             DC.Lam _ binding body ->
               let var = DC.V (DC.functionBindingVariable binding) 0
               in go (DC.subst var x' body)
             DC.ListFold
               | [_typeA, listExpr, _typeB, fn, z] <- spineArgs
               , DC.ListLit _ items <- peelOuter (go listExpr) ->
                   go (foldr (\elt acc -> DC.App (DC.App fn elt) acc) z (F.toList items))
             _ -> DC.App f' x'

      DC.Let binding body ->
        let var = DC.V (DC.variable binding) 0
            val = go (DC.value binding)
        in go (DC.subst var val body)

      DC.Field e fs ->
        let e' = go e
        in case peelOuter e' of
             DC.RecordLit m
               | Just rf <- DMap.lookup (DC.fieldSelectionLabel fs) m ->
                   go (DC.recordFieldValue rf)
             _ -> DC.Field e' fs

      DC.RecordLit m ->
        DC.RecordLit (fmap (\rf -> rf { DC.recordFieldValue = go (DC.recordFieldValue rf) }) m)

      DC.ListLit ann es ->
        DC.ListLit (fmap go ann) (fmap go es)

      DC.ListAppend l r ->
        case (peelOuter (go l), peelOuter (go r)) of
          (DC.ListLit ann ls, DC.ListLit _ rs) -> DC.ListLit ann (ls <> rs)
          (l', r')                             -> DC.ListAppend l' r'

      DC.Prefer cs pref l r ->
        let l' = go l
            r' = go r
        in case (peelOuter l', peelOuter r') of
             (DC.RecordLit ml, DC.RecordLit mr) ->
               -- Reattach the left-hand outer Note so an assertion built as
               -- @<assertion> // { module = Some "x" }@ keeps the
               -- assertion's original source location after Spec.module_
               -- has been β-reduced.
               carryOuterNote l' (DC.RecordLit (DMap.union mr ml))
             _ -> DC.Prefer cs pref l' r'

      DC.Annot e _ -> go e

      _ -> expr

    peelOuter (DC.Note _ e) = peelOuter e
    peelOuter e             = e

    -- Wrap @new@ with the outermost 'Note' that appears on @orig@, so
    -- structural reductions (record merge, list-fold step) do not strip
    -- the source location attached to the operand.
    carryOuterNote (DC.Note s _) new = DC.Note s new
    carryOuterNote _             new = new

    -- Collect the head of an application spine (App f x → … → App (App f x1) x2)
    -- so multi-argument builtins like @List/fold@ can be matched once their
    -- whole argument list is in hand.
    collectAppHead (DC.App f _) = collectAppHead f
    collectAppHead (DC.Note _ e) = collectAppHead e
    collectAppHead e             = e

    collectAppArgs = reverse . spine
      where
        spine (DC.App f x)  = x : spine f
        spine (DC.Note _ e) = spine e
        spine _             = []

-- | Splice the locations produced by 'extractAssertionLocs' back into the
-- decoded 'PlanFile'. The two share an indexing convention
-- @(mappingIdx, assertionIdx)@ so order-preserving Dhall decoders keep the
-- correspondence intact.
attachLocs :: Map (Int, Int) SourceLoc -> PlanFile -> PlanFile
attachLocs locs pf = pf
  { pfMappings =
      [ m { mAssertions =
              [ a { aSourceLocs = maybeToList (Map.lookup (mIdx, aIdx) locs) }
              | (aIdx, a) <- zip [0 ..] (mAssertions m)
              ]
          }
      | (mIdx, m) <- zip [0 ..] (pfMappings pf)
      ]
  }
