module Roundtrip.DhallEncodingTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Dhall
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.IR

tests :: TestTree
tests = testGroup "Dhall round-trip"
  [ testCase "AttrValue.AVText"  (decodes "(< AVText : Text | AVNat : Natural | AVBool : Bool >).AVText \"hello\"" (AVText "hello"))
  , testCase "AttrValue.AVNat"   (decodes "(< AVText : Text | AVNat : Natural | AVBool : Bool >).AVNat 42"          (AVNat 42))
  , testCase "AttrValue.AVBool"  (decodes "(< AVText : Text | AVNat : Natural | AVBool : Bool >).AVBool True"       (AVBool True))
  , testCase "Selector.SelAll"   (decodes "(< SelAll | SelRole : Text | SelTag : Text | SelHost : Text >).SelAll"   SelAll)
  , testCase "Selector.SelRole"  (decodes "(< SelAll | SelRole : Text | SelTag : Text | SelHost : Text >).SelRole \"Web\"" (SelRole (Role "Web")))
  , testCase "Assertion record"
      (decodes
        "{ kind = \"package\", primaryKey = \"nginx\", attrs = toMap { installed = (< AVText : Text | AVNat : Natural | AVBool : Bool >).AVBool True } }"
        (Assertion "package" "nginx" (Map.fromList [("installed", AVBool True)]))
      )
  ]

decodes :: (Eq a, Show a, Dhall.FromDhall a) => Text -> a -> IO ()
decodes src expected = do
  actual <- Dhall.input Dhall.auto src
  assertEqual "round-trip" expected actual
