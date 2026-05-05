module Property.EmitTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.QuickCheck (Gen, choose, elements, listOf, oneof, property, vectorOf)
import Test.Tasty
import Test.Tasty.QuickCheck (testProperty, counterexample, forAll, Property)

import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Emit.Serverspec (AttrTag (..), serverspecSchema)
import PanInfraSpec.Scaffold.Defaults.Serverspec (defaultServerspecScaffold)
import PanInfraSpec.IR
import PanInfraSpec.Layout (defaultLayout)

tests :: TestTree
tests = testGroup "property"
  [ testProperty "emit total over schema-conforming assertions" prop_emit_total_for_valid
  , testProperty "conflicting attrs rejected"                   prop_conflict_caught
  , testProperty "no UNREACHABLE comment in emitted output"     prop_no_unreachable_in_output
  ]

dummyNode :: Node
dummyNode = Node
  { hostname         = "synth"
  , ip               = Nothing
  , role             = Role "synth"
  , tags             = []
  , customAttributes = []
  }

-- | Pick one schema-allowed @(kind, attrKey, AttrTag)@ triple. Wildcard kinds
-- (empty attr schema) are excluded — they have no enumerable @(key, tag)@
-- pairs and are exercised by 'genWildcardAssertion' instead.
genKindKeyTag :: Gen (Text, Text, AttrTag)
genKindKeyTag = do
  let enumerable =
        [ (kind, attrs)
        | (kind, attrs) <- Map.toAscList serverspecSchema
        , not (Map.null attrs)
        ]
  (kind, attrSchema) <- elements enumerable
  (key, tag)         <- elements (Map.toAscList attrSchema)
  pure (kind, key, tag)

-- | List of wildcard-schema kinds (empty attr map). For these, any AVText key
-- is accepted by the validator.
wildcardKinds :: [Text]
wildcardKinds =
  [ kind
  | (kind, attrs) <- Map.toAscList serverspecSchema
  , Map.null attrs
  ]

-- | Generate an 'AttrValue' matching the given 'AttrTag'. The compound tags
-- ('ATList', 'ATRecord', 'ATCompare') are unreachable from the current
-- schema but kept total so the function survives schema growth.
genValue :: AttrTag -> Gen AttrValue
genValue = \case
  ATBool    -> pure (AVBool True)
  ATNat     -> AVNat . fromIntegral <$> choose (0 :: Int, 65535)
  ATText    -> AVText . T.pack <$> shortAlphaNum
  ATSymbol  -> AVSymbol . T.pack <$> shortAlphaNum
  ATList    -> AVList <$> listOf genLeaf
  ATRecord  -> AVRecord . Map.fromList <$> listOf ((,) <$> (T.pack <$> shortAlphaNum) <*> genLeaf)
  ATCompare -> AVCompare <$> elements [OpLt, OpLe, OpGt, OpGe, OpEq] <*> genLeaf

-- | Generate a scalar 'AttrLeaf'. Used inside 'AVList' / 'AVRecord' / 'AVCompare'.
genLeaf :: Gen AttrLeaf
genLeaf = elements [ATText, ATNat, ATBool, ATSymbol] >>= \case
  ATText    -> ALText   . T.pack <$> shortAlphaNum
  ATNat     -> ALNat    . fromIntegral <$> choose (0 :: Int, 65535)
  ATBool    -> pure (ALBool True)
  ATSymbol  -> ALSymbol . T.pack <$> shortAlphaNum
  ATList    -> ALText   . T.pack <$> shortAlphaNum  -- unreachable; satisfies totality
  ATRecord  -> ALText   . T.pack <$> shortAlphaNum  -- unreachable; satisfies totality
  ATCompare -> ALText   . T.pack <$> shortAlphaNum  -- unreachable; satisfies totality

shortAlphaNum :: Gen String
shortAlphaNum = do
  n <- choose (1, 12)
  vectorOf n (elements (['a'..'z'] <> ['0'..'9'] <> "-_/"))

-- | Generate a primary key suitable for the given kind.
genPrimaryKey :: Text -> Gen Text
genPrimaryKey "port" = T.pack . show <$> choose (1 :: Int, 65535)
genPrimaryKey _      = T.pack <$> shortAlphaNum

-- | Generate an Assertion that satisfies the Serverspec schema. Mixes
-- enumerable-schema kinds with wildcard-schema kinds so both code paths in
-- the emitter are exercised.
genValidAssertion :: Gen Assertion
genValidAssertion
  | null wildcardKinds = genEnumerableAssertion
  | otherwise          = oneof [genEnumerableAssertion, genWildcardAssertion]

genEnumerableAssertion :: Gen Assertion
genEnumerableAssertion = do
  (kind, key, tag) <- genKindKeyTag
  pk               <- genPrimaryKey kind
  val              <- genValue tag
  pure (Assertion kind pk (Map.singleton key val) Nothing)

-- | Wildcard-kind assertion: dynamic attr key, AVText value.
genWildcardAssertion :: Gen Assertion
genWildcardAssertion = do
  kind <- elements wildcardKinds
  pk   <- genPrimaryKey kind
  key  <- T.pack <$> shortAlphaNum
  val  <- AVText . T.pack <$> shortAlphaNum
  pure (Assertion kind pk (Map.singleton key val) Nothing)

-- | Two assertions sharing @(kind, primaryKey, attrKey)@ but disagreeing on
-- the value. Builds the conflict the layer-3 fail-safe must catch.
genConflictingPair :: Gen (Assertion, Assertion)
genConflictingPair = do
  -- Choose a kind whose schema admits at least one Nat or Text attr; Bool
  -- attrs only have one value (True) under our smart constructors so they
  -- can't naturally conflict.
  let nonBoolEntries =
        [ (k, key, tag)
        | (k, attrs) <- Map.toAscList serverspecSchema
        , (key, tag) <- Map.toAscList attrs
        , tag /= ATBool
        ]
  (kind, key, tag) <- elements nonBoolEntries
  pk               <- genPrimaryKey kind
  v1               <- genValue tag
  v2               <- differentFrom (genValue tag) v1
  pure ( Assertion kind pk (Map.singleton key v1) Nothing
       , Assertion kind pk (Map.singleton key v2) Nothing
       )

-- | Roll the generator until it produces a value distinct from @v@, or fall
-- back to a deterministic perturbation after the retry budget is exhausted.
-- The naive @if v == v' then loop else pure v'@ shape was observed to hang
-- for >17 minutes on Windows runners when the generator's effective domain
-- is small (e.g. an empty 'AVList' or a single 'AVCompare' op).
differentFrom :: Gen AttrValue -> AttrValue -> Gen AttrValue
differentFrom g v = go (30 :: Int)
  where
    go 0 = pure (bumpAttrValue v)
    go n = do
      v' <- g
      if v == v' then go (n - 1) else pure v'

-- | Deterministic perturbation that preserves the 'AttrValue' constructor
-- (so the result still matches the schema 'AttrTag' the caller asked for)
-- while guaranteeing @bumpAttrValue v /= v@.
bumpAttrValue :: AttrValue -> AttrValue
bumpAttrValue = \case
  AVText    t    -> AVText   (t <> "_x")
  AVNat     n    -> AVNat    (n + 1)
  AVBool    b    -> AVBool   (not b)
  AVSymbol  t    -> AVSymbol (t <> "_x")
  AVList    xs   -> AVList   (ALText "__paninfra_bump__" : xs)
  AVRecord  m    -> AVRecord (Map.insert "__paninfra_bump__" (ALText "__bumped__") m)
  AVCompare op l -> AVCompare (rotateOp op) l
  where
    rotateOp = \case
      OpLt    -> OpLe
      OpLe    -> OpGt
      OpGt    -> OpGe
      OpGe    -> OpEq
      OpEq    -> OpMatch
      OpMatch -> OpLt

-- | Dedupe by @(kind, primaryKey, attrKey)@ so that random list generation
-- doesn't accidentally synthesize conflicting assertions for the same
-- resource — that's a separate property ('prop_conflict_caught').
genValidAssertionList :: Gen [Assertion]
genValidAssertionList = dedupe <$> listOf genValidAssertion
  where
    dedupe = Map.elems . Map.fromList . map keyed
    keyed a@(Assertion k pk attrs _) =
      let attrKey = case Map.toAscList attrs of
                      ((ak, _) : _) -> ak
                      []            -> ""
      in ((k, pk, attrKey), a)

-- | For any list of schema-conforming, non-conflicting assertions, the
-- emitter must succeed.
prop_emit_total_for_valid :: Property
prop_emit_total_for_valid = forAll genValidAssertionList $ \as ->
  let ep = ExecutionPlan "serverspec" [Job dummyNode as]
  in case emitFor defaultServerspecScaffold defaultLayout ep of
       Right _ -> property True
       Left e  -> counterexample
         ("unexpected Left from emit: " <> T.unpack e <> "; input=" <> show as)
         False

-- | A conflicting pair must always produce a Left mentioning the conflict.
prop_conflict_caught :: Property
prop_conflict_caught = forAll genConflictingPair $ \(a, b) ->
  let ep = ExecutionPlan "serverspec" [Job dummyNode [a, b]]
  in case emitFor defaultServerspecScaffold defaultLayout ep of
       Left e | "conflicting attribute" `T.isInfixOf` e -> property True
       other -> counterexample
         ("expected Left with 'conflicting attribute', got: " <> show other
            <> "; input=" <> show (a, b))
         False

-- | The emitter has a catch-all in 'formatItLine' that prints
-- @# UNREACHABLE: ...@ for any (kind, attrKey) it forgot to handle. That
-- comment must never appear in real output: layer-3 validation rejects
-- unknown keys upfront, so anything that survives validation must have a
-- dedicated formatter. This property guards against silently regressing
-- when a new 'AttrValue' constructor is added but a corresponding pattern
-- is forgotten.
prop_no_unreachable_in_output :: Property
prop_no_unreachable_in_output = forAll genValidAssertionList $ \as ->
  let ep = ExecutionPlan "serverspec" [Job dummyNode as]
  in case emitFor defaultServerspecScaffold defaultLayout ep of
       Right outs ->
         let combined = T.concat (Map.elems outs)
         in if "UNREACHABLE" `T.isInfixOf` combined
              then counterexample
                     ("UNREACHABLE leaked into output: " <> T.unpack combined
                        <> "; input=" <> show as)
                     False
              else property True
       Left _ -> property True  -- emit failures are checked elsewhere
