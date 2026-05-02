module Property.EmitTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.QuickCheck (Gen, choose, elements, listOf, property, vectorOf)
import Test.Tasty
import Test.Tasty.QuickCheck (testProperty, counterexample, forAll, Property)

import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Emit.Serverspec (AttrTag (..), serverspecSchema)
import PanInfraSpec.IR

tests :: TestTree
tests = testGroup "property"
  [ testProperty "emit total over schema-conforming assertions" prop_emit_total_for_valid
  , testProperty "conflicting attrs rejected"                   prop_conflict_caught
  ]

dummyNode :: Node
dummyNode = Node
  { hostname = "synth"
  , ip       = Nothing
  , role     = Role "synth"
  , tags     = []
  }

-- | Pick one schema-allowed @(kind, attrKey, AttrTag)@ triple.
genKindKeyTag :: Gen (Text, Text, AttrTag)
genKindKeyTag = do
  (kind, attrSchema) <- elements (Map.toAscList serverspecSchema)
  (key, tag)         <- elements (Map.toAscList attrSchema)
  pure (kind, key, tag)

-- | Generate an 'AttrValue' matching the given 'AttrTag'.
genValue :: AttrTag -> Gen AttrValue
genValue = \case
  ATBool -> pure (AVBool True)
  ATNat  -> AVNat . fromIntegral <$> choose (0 :: Int, 65535)
  ATText -> AVText . T.pack <$> shortAlphaNum

shortAlphaNum :: Gen String
shortAlphaNum = do
  n <- choose (1, 12)
  vectorOf n (elements (['a'..'z'] <> ['0'..'9'] <> "-_/"))

-- | Generate a primary key suitable for the given kind.
genPrimaryKey :: Text -> Gen Text
genPrimaryKey "port" = T.pack . show <$> choose (1 :: Int, 65535)
genPrimaryKey _      = T.pack <$> shortAlphaNum

-- | Generate an Assertion that satisfies the Serverspec schema.
genValidAssertion :: Gen Assertion
genValidAssertion = do
  (kind, key, tag) <- genKindKeyTag
  pk               <- genPrimaryKey kind
  val              <- genValue tag
  pure (Assertion kind pk (Map.singleton key val))

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
  v2               <- genValue tag `differentFrom` v1
  pure ( Assertion kind pk (Map.singleton key v1)
       , Assertion kind pk (Map.singleton key v2)
       )
  where
    differentFrom :: Gen AttrValue -> AttrValue -> Gen AttrValue
    differentFrom g v = do
      v' <- g
      if v == v' then differentFrom g v else pure v'

-- | Dedupe by @(kind, primaryKey, attrKey)@ so that random list generation
-- doesn't accidentally synthesize conflicting assertions for the same
-- resource — that's a separate property ('prop_conflict_caught').
genValidAssertionList :: Gen [Assertion]
genValidAssertionList = dedupe <$> listOf genValidAssertion
  where
    dedupe = Map.elems . Map.fromList . map keyed
    keyed a@(Assertion k pk attrs) =
      let attrKey = case Map.toAscList attrs of
                      ((ak, _) : _) -> ak
                      []            -> ""
      in ((k, pk, attrKey), a)

-- | For any list of schema-conforming, non-conflicting assertions, the
-- emitter must succeed.
prop_emit_total_for_valid :: Property
prop_emit_total_for_valid = forAll genValidAssertionList $ \as ->
  let ep = ExecutionPlan "serverspec" [Job dummyNode as]
  in case emitFor ep of
       Right _ -> property True
       Left e  -> counterexample
         ("unexpected Left from emit: " <> T.unpack e <> "; input=" <> show as)
         False

-- | A conflicting pair must always produce a Left mentioning the conflict.
prop_conflict_caught :: Property
prop_conflict_caught = forAll genConflictingPair $ \(a, b) ->
  let ep = ExecutionPlan "serverspec" [Job dummyNode [a, b]]
  in case emitFor ep of
       Left e | "conflicting attribute" `T.isInfixOf` e -> property True
       other -> counterexample
         ("expected Left with 'conflicting attribute', got: " <> show other
            <> "; input=" <> show (a, b))
         False
