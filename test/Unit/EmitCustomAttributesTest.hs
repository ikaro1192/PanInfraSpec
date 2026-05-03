module Unit.EmitCustomAttributesTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Scaffold (defaultServerspecScaffold)
import PanInfraSpec.IR hiding (Assertion)
import qualified PanInfraSpec.IR as IR
import PanInfraSpec.Layout (defaultLayout)

tests :: TestTree
tests = testGroup "customAttributes & ALRubyExpr"
  [ testCase "mysql_config CompareExpr renders bare Ruby expression"  mysqlCompareExpr
  , testCase "php_config CompareExpr renders bare Ruby expression"    phpCompareExpr
  , testCase "x509_certificate CompareExpr renders bare Ruby expression" x509CompareExpr
  -- preamble generation
  , testCase "preamble bound after spec_helper require"    preambleBoundAfterRequire
  , testCase "preamble emits one line per customAttribute" preambleMultiAttr
  , testCase "preamble omitted for empty customAttributes" preambleOmittedForEmpty
  , testCase "preamble: command is shell-quoted via rubyString" preambleEscapesQuotes
  -- validation
  , testCase "rejects empty customAttribute name"          rejectsEmptyName
  , testCase "rejects empty customAttribute command"       rejectsEmptyCommand
  , testCase "rejects duplicate customAttribute name"      rejectsDuplicateName
  , testCase "rejects invalid Ruby identifier name"        rejectsInvalidIdentifier
  ]

-- | Build a single-host single-assertion plan, run the emitter, and return the
-- generated host spec body as Text.
emitOne :: Node -> IR.Assertion -> Either Text Text
emitOne node assertion =
  let ep = ExecutionPlan "serverspec" [Job node [assertion]]
  in case emitFor defaultServerspecScaffold defaultLayout ep of
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
  Left  e -> assertFailure ("expected Right with " <> show needle <> ", got Left " <> show e)
  Right t
    | needle `T.isInfixOf` t -> pure ()
    | otherwise -> assertFailure
        ("expected output to contain " <> show needle <> "; got:\n" <> T.unpack t)

-- | mysql_config + AVCompare OpGt (ALRubyExpr ...)  →
--   its(:value) { should be > <expr> }
mysqlCompareExpr :: IO ()
mysqlCompareExpr =
  let assertion = IR.Assertion "mysql_config" "innodb_buffer_pool_size"
        (Map.singleton "value"
           (AVCompare OpGt (ALRubyExpr "paninfraspec_total_ram_kb.to_i * 1024 * 70 / 100"))) Nothing
   in assertContains
        "its(:value) { should be > paninfraspec_total_ram_kb.to_i * 1024 * 70 / 100 }"
        (emitOne (emptyNode "web01") assertion)

-- | php_config + AVCompare OpLe (ALRubyExpr ...)
phpCompareExpr :: IO ()
phpCompareExpr =
  let assertion = IR.Assertion "php_config" "memory_limit"
        (Map.singleton "value"
           (AVCompare OpLe (ALRubyExpr "paninfraspec_php_max_mb.to_i"))) Nothing
   in assertContains
        "its(:value) { should be <= paninfraspec_php_max_mb.to_i }"
        (emitOne (emptyNode "web01") assertion)

-- | x509_certificate + AVCompare OpGe (ALRubyExpr ...)
x509CompareExpr :: IO ()
x509CompareExpr =
  let assertion = IR.Assertion "x509_certificate" "/etc/ssl/cert.pem"
        (Map.singleton "validity_in_days"
           (AVCompare OpGe (ALRubyExpr "paninfraspec_min_cert_days.to_i"))) Nothing
   in assertContains
        "its(:validity_in_days) { should be >= paninfraspec_min_cert_days.to_i }"
        (emitOne (emptyNode "web01") assertion)

-- | Trivial command assertion used as a stable describe block while we focus
-- on preamble behaviour.
unameAssertion :: IR.Assertion
unameAssertion = IR.Assertion "command" "uname -a"
  (Map.singleton "exit-status" (AVNat 0)) Nothing

withCustom :: [CustomAttribute] -> Node -> Node
withCustom cas n = n { customAttributes = cas }

-- | preamble line lands between `require 'spec_helper'` and the first describe.
preambleBoundAfterRequire :: IO ()
preambleBoundAfterRequire =
  let node = withCustom
        [CustomAttribute "total_ram_kb" "awk '/MemTotal/ {print $2}' /proc/meminfo"]
        (emptyNode "web01")
   in case emitOne node unameAssertion of
        Left e -> assertFailure ("emit failed: " <> show e)
        Right t ->
          let ls = T.lines t
              -- find the first describe block start
              hasDescribe = any (\l -> "describe " `T.isPrefixOf` l) ls
              hasRequire  = any (\l -> "require 'spec_helper'" `T.isPrefixOf` l) ls
              hasPreamble = any (\l -> "paninfraspec_total_ram_kb" `T.isInfixOf` l) ls
              orderOk =
                let ix p = length (takeWhile (not . p) ls)
                    irq  = ix (\l -> "require 'spec_helper'" `T.isPrefixOf` l)
                    ipre = ix (\l -> "paninfraspec_total_ram_kb" `T.isInfixOf` l)
                    idsc = ix (\l -> "describe " `T.isPrefixOf` l)
                in irq < ipre && ipre < idsc
          in assertBool
               ("require/preamble/describe order broken in:\n" <> T.unpack t)
               (hasRequire && hasPreamble && hasDescribe && orderOk)

-- | Two customAttributes produce two preamble lines, in declaration order.
preambleMultiAttr :: IO ()
preambleMultiAttr =
  let node = withCustom
        [ CustomAttribute "total_ram_kb" "awk '/MemTotal/ {print $2}' /proc/meminfo"
        , CustomAttribute "cpu_count"    "nproc"
        ]
        (emptyNode "web01")
   in case emitOne node unameAssertion of
        Left e  -> assertFailure ("emit failed: " <> show e)
        Right t -> do
          assertBool "first preamble missing" $
            "paninfraspec_total_ram_kb = " `T.isInfixOf` t
          assertBool "second preamble missing" $
            "paninfraspec_cpu_count = " `T.isInfixOf` t
          let firstIdx  = T.length (fst (T.breakOn "paninfraspec_total_ram_kb" t))
              secondIdx = T.length (fst (T.breakOn "paninfraspec_cpu_count" t))
          assertBool "preamble order should follow declaration"
                    (firstIdx < secondIdx)

-- | Empty customAttributes: no preamble line emitted.
preambleOmittedForEmpty :: IO ()
preambleOmittedForEmpty =
  case emitOne (emptyNode "web01") unameAssertion of
    Left e  -> assertFailure ("emit failed: " <> show e)
    Right t -> assertBool
      ("preamble unexpectedly emitted in:\n" <> T.unpack t)
      (not ("paninfraspec_" `T.isInfixOf` t))

-- | Single-quotes inside the command string are escaped via rubyString.
preambleEscapesQuotes :: IO ()
preambleEscapesQuotes =
  let node = withCustom
        [CustomAttribute "msg" "echo 'hi'"]
        (emptyNode "web01")
   in case emitOne node unameAssertion of
        Left e  -> assertFailure ("emit failed: " <> show e)
        Right t -> assertBool
          ("expected escaped single-quote in:\n" <> T.unpack t)
          ("'echo \\'hi\\''" `T.isInfixOf` t)

assertEmitLeftContains :: Text -> Node -> IO ()
assertEmitLeftContains needle node =
  case emitOne node unameAssertion of
    Right t -> assertFailure
      ("expected Left containing " <> show needle <> ", got Right:\n" <> T.unpack t)
    Left e
      | needle `T.isInfixOf` e -> pure ()
      | otherwise -> assertFailure
          ("expected error containing " <> show needle <> ", got: " <> show e)

rejectsEmptyName :: IO ()
rejectsEmptyName =
  assertEmitLeftContains "non-empty" $
    withCustom [CustomAttribute "" "echo hi"] (emptyNode "web01")

rejectsEmptyCommand :: IO ()
rejectsEmptyCommand =
  assertEmitLeftContains "non-empty" $
    withCustom [CustomAttribute "x" ""] (emptyNode "web01")

rejectsDuplicateName :: IO ()
rejectsDuplicateName =
  assertEmitLeftContains "duplicate" $
    withCustom
      [ CustomAttribute "x" "echo a"
      , CustomAttribute "x" "echo b"
      ]
      (emptyNode "web01")

rejectsInvalidIdentifier :: IO ()
rejectsInvalidIdentifier = do
  assertEmitLeftContains "valid" $
    withCustom [CustomAttribute "9foo" "echo a"] (emptyNode "web01")
  assertEmitLeftContains "valid" $
    withCustom [CustomAttribute "with space" "echo a"] (emptyNode "web01")
  assertEmitLeftContains "valid" $
    withCustom [CustomAttribute "Foo" "echo a"] (emptyNode "web01")
