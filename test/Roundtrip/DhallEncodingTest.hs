module Roundtrip.DhallEncodingTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Dhall
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.IR
import qualified PanInfraSpec.IR as IR

-- | The full @AttrValue@ union literal used by the Dhall prelude. Inlined
-- here so each test case can disambiguate which constructor it picks.
attrValueU :: Text
attrValueU =
  "< AVText : Text | AVNat : Natural | AVBool : Bool \
  \| AVSymbol : Text \
  \| AVList : List < ALText : Text | ALNat : Natural | ALBool : Bool | ALSymbol : Text | ALRegex : Text | ALRubyExpr : Text > \
  \| AVRecord : List { mapKey : Text, mapValue : < ALText : Text | ALNat : Natural | ALBool : Bool | ALSymbol : Text | ALRegex : Text | ALRubyExpr : Text > } \
  \| AVCompare : { op : < Lt | Le | Gt | Ge | Eq | Match >, value : < ALText : Text | ALNat : Natural | ALBool : Bool | ALSymbol : Text | ALRegex : Text | ALRubyExpr : Text > } \
  \>"

attrLeafU :: Text
attrLeafU = "< ALText : Text | ALNat : Natural | ALBool : Bool | ALSymbol : Text | ALRegex : Text | ALRubyExpr : Text >"

compareOpU :: Text
compareOpU = "< Lt | Le | Gt | Ge | Eq | Match >"

tests :: TestTree
tests = testGroup "Dhall round-trip"
  [ testCase "AttrValue.AVText"  (decodes ("(" <> attrValueU <> ").AVText \"hello\"") (AVText "hello"))
  , testCase "AttrValue.AVNat"   (decodes ("(" <> attrValueU <> ").AVNat 42")          (AVNat 42))
  , testCase "AttrValue.AVBool"  (decodes ("(" <> attrValueU <> ").AVBool True")       (AVBool True))
  , testCase "AttrValue.AVSymbol"
      (decodes ("(" <> attrValueU <> ").AVSymbol \"type_dword\"") (AVSymbol "type_dword"))
  , testCase "AttrValue.AVList"
      (decodes
        ("(" <> attrValueU <> ").AVList \
         \[ (" <> attrLeafU <> ").ALText \"name\" \
         \, (" <> attrLeafU <> ").ALSymbol \"type_dword\" \
         \, (" <> attrLeafU <> ").ALNat 1 \
         \]")
        (AVList [ALText "name", ALSymbol "type_dword", ALNat 1])
      )
  , testCase "AttrValue.AVRecord"
      (decodes
        ("(" <> attrValueU <> ").AVRecord \
         \(toMap \
         \  { dest = (" <> attrLeafU <> ").ALText \"192.168.0.0/24\" \
         \  , gw   = (" <> attrLeafU <> ").ALText \"192.168.0.1\" \
         \  } \
         \)")
        (AVRecord (Map.fromList
          [ ("dest", ALText "192.168.0.0/24")
          , ("gw",   ALText "192.168.0.1")
          ]))
      )
  , testCase "AttrValue.AVCompare"
      (decodes
        ("(" <> attrValueU <> ").AVCompare \
         \{ op = (" <> compareOpU <> ").Gt \
         \, value = (" <> attrLeafU <> ").ALNat 30 \
         \}")
        (AVCompare OpGt (ALNat 30))
      )
  , testCase "CompareOp.Gt"      (decodes ("(" <> compareOpU <> ").Gt") OpGt)
  , testCase "AttrLeaf.ALSymbol" (decodes ("(" <> attrLeafU <> ").ALSymbol \"foo\"") (ALSymbol "foo"))
  , testCase "AttrLeaf.ALRubyExpr"
      (decodes ("(" <> attrLeafU <> ").ALRubyExpr \"x.to_i * 2\"") (ALRubyExpr "x.to_i * 2"))
  , testCase "AttrValue.AVCompare with ALRubyExpr"
      (decodes
        ("(" <> attrValueU <> ").AVCompare \
         \{ op = (" <> compareOpU <> ").Gt \
         \, value = (" <> attrLeafU <> ").ALRubyExpr \"paninfraspec_x.to_i\" \
         \}")
        (AVCompare OpGt (ALRubyExpr "paninfraspec_x.to_i"))
      )
  , testCase "CustomAttribute round-trip"
      (decodes
        "{ name = \"total_ram_kb\", command = \"awk '/MemTotal/' /proc/meminfo\" }"
        (CustomAttribute "total_ram_kb" "awk '/MemTotal/' /proc/meminfo")
      )
  , testCase "Selector.SelAll"   (decodes "(< SelAll | SelRole : Text | SelTag : Text | SelHost : Text >).SelAll"   SelAll)
  , testCase "Selector.SelRole"  (decodes "(< SelAll | SelRole : Text | SelTag : Text | SelHost : Text >).SelRole \"Web\"" (SelRole (Role "Web")))
  , testCase "Assertion record (no module label)"
      (decodes
        ("{ kind = \"package\", primaryKey = \"nginx\", attrs = toMap { installed = (" <> attrValueU <> ").AVBool True }, module = None Text }")
        (Assertion "package" "nginx" (Map.fromList [("installed", AVBool True)]) Nothing)
      )
  , testCase "Assertion record (with module label)"
      (decodes
        ("{ kind = \"service\", primaryKey = \"nginx\", attrs = toMap { running = (" <> attrValueU <> ").AVBool True }, module = Some \"nginx\" }")
        (Assertion "service" "nginx" (Map.fromList [("running", AVBool True)]) (Just "nginx"))
      )
  , testCase "Spec.module_ tags every assertion in the list"
      specModuleHelper
  , testCase "Node -> Text via Dhall.function (hostname projection)" $ do
      f <- Dhall.input
        (Dhall.function nodeEncoder Dhall.strictText)
        "\\(n : { hostname : Text, ip : Optional Text, role : Text, tags : List Text, customAttributes : List { name : Text, command : Text } }) -> n.hostname"
      assertEqual "hostname projection"
        "web01"
        (f (Node "web01" Nothing (Role "Web") [] []))
  , testCase "Node -> Text via Dhall.function (role/hostname interpolation)" $ do
      f <- Dhall.input
        (Dhall.function nodeEncoder Dhall.strictText)
        "\\(n : { hostname : Text, ip : Optional Text, role : Text, tags : List Text, customAttributes : List { name : Text, command : Text } }) -> \"${n.role}/${n.hostname}_spec.rb\""
      assertEqual "by-role layout"
        "Web/web01_spec.rb"
        (f (Node "web01" (Just "10.0.1.10") (Role "Web") ["frontend"] []))
  ]

decodes :: (Eq a, Show a, Dhall.FromDhall a) => Text -> a -> IO ()
decodes src expected = do
  actual <- Dhall.input Dhall.auto src
  assertEqual "round-trip" expected actual

-- | Build a `[ Spec.package "nginx" ..., Spec.service "nginx" ... ]` and
-- pipe it through `Spec.module_ "nginx"`; every element should come back
-- with `aModule = Just "nginx"`.
specModuleHelper :: IO ()
specModuleHelper = do
  -- `Dhall.input` resolves imports relative to the CWD (project root in
  -- the cabal test harness), so use `./dhall/...` rather than `../dhall/...`.
  let src = T.intercalate "\n"
        [ "let Spec = ./dhall/Serverspec.dhall"
        , "in  Spec.module_ \"nginx\""
        , "      [ Spec.package \"nginx\" Spec.PackageState.Installed"
        , "      , Spec.service \"nginx\" Spec.ServiceState.Running"
        , "      ]"
        ]
  -- Run from project root (where dhall/ lives) — same convention as the
  -- ScaffoldTest fixture loader.
  result <- Dhall.input Dhall.auto src
  let assertions = result :: [IR.Assertion]
  length assertions @?= 2
  mapM_ (\a -> aModule a @?= Just "nginx") assertions
  -- preserve original kinds in the same order
  map aKind assertions @?= ["package", "service"]
