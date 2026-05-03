module Roundtrip.DhallEncodingTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Dhall
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.IR

-- | The full @AttrValue@ union literal used by the Dhall prelude. Inlined
-- here so each test case can disambiguate which constructor it picks.
attrValueU :: Text
attrValueU =
  "< AVText : Text | AVNat : Natural | AVBool : Bool \
  \| AVSymbol : Text \
  \| AVList : List < ALText : Text | ALNat : Natural | ALBool : Bool | ALSymbol : Text | ALRegex : Text > \
  \| AVRecord : List { mapKey : Text, mapValue : < ALText : Text | ALNat : Natural | ALBool : Bool | ALSymbol : Text | ALRegex : Text > } \
  \| AVCompare : { op : < Lt | Le | Gt | Ge | Eq | Match >, value : < ALText : Text | ALNat : Natural | ALBool : Bool | ALSymbol : Text | ALRegex : Text > } \
  \>"

attrLeafU :: Text
attrLeafU = "< ALText : Text | ALNat : Natural | ALBool : Bool | ALSymbol : Text | ALRegex : Text >"

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
  , testCase "Selector.SelAll"   (decodes "(< SelAll | SelRole : Text | SelTag : Text | SelHost : Text >).SelAll"   SelAll)
  , testCase "Selector.SelRole"  (decodes "(< SelAll | SelRole : Text | SelTag : Text | SelHost : Text >).SelRole \"Web\"" (SelRole (Role "Web")))
  , testCase "Assertion record"
      (decodes
        ("{ kind = \"package\", primaryKey = \"nginx\", attrs = toMap { installed = (" <> attrValueU <> ").AVBool True } }")
        (Assertion "package" "nginx" (Map.fromList [("installed", AVBool True)]))
      )
  , testCase "Node -> Text via Dhall.function (hostname projection)" $ do
      f <- Dhall.input
        (Dhall.function nodeEncoder Dhall.strictText)
        "\\(n : { hostname : Text, ip : Optional Text, role : Text, tags : List Text }) -> n.hostname"
      assertEqual "hostname projection"
        "web01"
        (f (Node "web01" Nothing (Role "Web") []))
  , testCase "Node -> Text via Dhall.function (role/hostname interpolation)" $ do
      f <- Dhall.input
        (Dhall.function nodeEncoder Dhall.strictText)
        "\\(n : { hostname : Text, ip : Optional Text, role : Text, tags : List Text }) -> \"${n.role}/${n.hostname}_spec.rb\""
      assertEqual "by-role layout"
        "Web/web01_spec.rb"
        (f (Node "web01" (Just "10.0.1.10") (Role "Web") ["frontend"]))
  ]

decodes :: (Eq a, Show a, Dhall.FromDhall a) => Text -> a -> IO ()
decodes src expected = do
  actual <- Dhall.input Dhall.auto src
  assertEqual "round-trip" expected actual
