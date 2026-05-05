module Unit.EmitTypedExprTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Emit.SourceMap (defaultEmitOptions)
import PanInfraSpec.Scaffold.Defaults.Serverspec (defaultServerspecScaffold)
import PanInfraSpec.IR hiding (Assertion)
import qualified PanInfraSpec.IR as IR
import PanInfraSpec.Layout (defaultLayout)

tests :: TestTree
tests = testGroup "typed expression IR (ALExpr)"
  [ testCase "ExprFactInt renders <name>.to_i"
      factIntRenders
  , testCase "ExprFactIntScaled with empty muls renders <name>.to_i / divisor"
      scaledEmptyMulsRenders
  , testCase "ExprFactIntScaled with multiple muls preserves order"
      scaledMultiMulsRenders
  , testCase "memory % pattern is byte-identical to the escape-hatch form"
      memoryPercentByteIdentical
  , testCase "ExprAdd of two fact references renders subtraction"
      addRenders
  , testCase "ExprSub renders subtraction of two fact references"
      subRenders
  , testCase "ExprMul of literal and fact renders multiplication"
      mulRenders
  , testCase "ExprDiv of fact by literal renders integer division"
      divRenders
  ]

emitOne :: Node -> IR.Assertion -> Either Text Text
emitOne node assertion =
  let ep = ExecutionPlan "serverspec" [Job node [assertion]]
  in case emitFor defaultServerspecScaffold defaultLayout ep defaultEmitOptions of
       Left e     -> Left e
       Right outs -> case Map.lookup (T.unpack (hostname node) <> "_spec.rb") outs of
         Just t  -> Right t
         Nothing -> Left ("missing spec for " <> hostname node)

emptyNode :: Text -> Node
emptyNode h = Node
  { hostname         = h
  , ip               = Nothing
  , role             = Role "Web"
  , tags             = []
  , customAttributes = []
  }

assertContains :: Text -> Either Text Text -> IO ()
assertContains needle = \case
  Left  e -> assertFailure
    ("expected Right with " <> show needle <> ", got Left " <> show e)
  Right t
    | needle `T.isInfixOf` t -> pure ()
    | otherwise -> assertFailure
        ("expected output to contain " <> show needle <> "; got:\n" <> T.unpack t)

factIntRenders :: IO ()
factIntRenders =
  let assertion = IR.mkAssertion "php_config" "memory_limit"
        (Map.singleton "value"
           (AVCompare OpLe (ALExpr (ExprFactInt "php_max_mb")))) Nothing
   in assertContains
        "its(:value) { should be <= paninfraspec_php_max_mb.to_i }"
        (emitOne (emptyNode "web01") assertion)

scaledEmptyMulsRenders :: IO ()
scaledEmptyMulsRenders =
  let assertion = IR.mkAssertion "x509_certificate" "/etc/ssl/cert.pem"
        (Map.singleton "validity_in_days"
           (AVCompare OpGe (ALExpr (ExprFactIntScaled "min_cert_days" [] 1)))) Nothing
   in assertContains
        "its(:validity_in_days) { should be >= paninfraspec_min_cert_days.to_i / 1 }"
        (emitOne (emptyNode "web01") assertion)

scaledMultiMulsRenders :: IO ()
scaledMultiMulsRenders =
  let assertion = IR.mkAssertion "mysql_config" "innodb_buffer_pool_size"
        (Map.singleton "value"
           (AVCompare OpGt (ALExpr (ExprFactIntScaled "ram" [2, 3, 5] 7)))) Nothing
   in assertContains
        "its(:value) { should be > paninfraspec_ram.to_i * 2 * 3 * 5 / 7 }"
        (emitOne (emptyNode "web01") assertion)

memoryPercentByteIdentical :: IO ()
memoryPercentByteIdentical =
  let assertion = IR.mkAssertion "mysql_config" "innodb_buffer_pool_size"
        (Map.singleton "value"
           (AVCompare OpGt
              (ALExpr (ExprFactIntScaled "total_ram_kb" [1024, 70] 100)))) Nothing
   in assertContains
        "its(:value) { should be > paninfraspec_total_ram_kb.to_i * 1024 * 70 / 100 }"
        (emitOne (emptyNode "web01") assertion)

mysqlExpr :: Expr -> IR.Assertion
mysqlExpr e = IR.mkAssertion "mysql_config" "k"
  (Map.singleton "value" (AVCompare OpEq (ALExpr e))) Nothing

addRenders :: IO ()
addRenders =
  let assertion = mysqlExpr (ExprAdd (OpFact "a") (OpFact "b"))
   in assertContains
        "its(:value) { should eq paninfraspec_a.to_i + paninfraspec_b.to_i }"
        (emitOne (emptyNode "web01") assertion)

subRenders :: IO ()
subRenders =
  let assertion = mysqlExpr (ExprSub (OpFact "total") (OpFact "free"))
   in assertContains
        "its(:value) { should eq paninfraspec_total.to_i - paninfraspec_free.to_i }"
        (emitOne (emptyNode "web01") assertion)

mulRenders :: IO ()
mulRenders =
  let assertion = mysqlExpr (ExprMul (OpLit 2) (OpFact "x"))
   in assertContains
        "its(:value) { should eq 2 * paninfraspec_x.to_i }"
        (emitOne (emptyNode "web01") assertion)

divRenders :: IO ()
divRenders =
  let assertion = mysqlExpr (ExprDiv (OpFact "total") (OpLit 2))
   in assertContains
        "its(:value) { should eq paninfraspec_total.to_i / 2 }"
        (emitOne (emptyNode "web01") assertion)
