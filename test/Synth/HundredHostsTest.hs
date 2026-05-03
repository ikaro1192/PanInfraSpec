module Synth.HundredHostsTest (tests) where

import Control.Monad (forM_)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Dhall (validate)
import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Scaffold (defaultServerspecScaffold)
import PanInfraSpec.IR
import PanInfraSpec.Layout (defaultLayout)
import PanInfraSpec.Resolve (resolve)

tests :: TestTree
tests = testGroup "synthetic"
  [ testCase "100-host inventory end-to-end" hundredHosts
  ]

-- | 100 nodes, 5 roles, alternating @metrics@ tag.
synthInventory :: [Node]
synthInventory =
  [ Node
      { hostname         = "h" <> T.pack (show i)
      , ip               = Just ("10.0." <> T.pack (show (i `div` 50)) <> "." <> T.pack (show (i `mod` 50)))
      , role             = roleFor i
      , tags             = if even i then ["metrics"] else []
      , customAttributes = []
      }
  | i <- [1 .. 100 :: Int]
  ]
  where
    roles = ["Web", "DB", "Cache", "Worker", "Edge"] :: [Text]
    roleFor i = Role (roles !! (i `mod` length roles))

synthPlan :: [Mapping]
synthPlan =
  [ Mapping SelAll
      [ Assertion "command" "uname -a"
          (Map.singleton "exit-status" (AVNat 0)) Nothing
      ]
  , Mapping (SelRole (Role "Web"))
      [ Assertion "package" "nginx"
          (Map.singleton "installed" (AVBool True)) Nothing
      , Assertion "service" "nginx"
          (Map.singleton "running" (AVBool True)) Nothing
      ]
  , Mapping (SelTag "metrics")
      [ Assertion "port" "9090"
          (Map.singleton "listening" (AVBool True)) Nothing
      ]
  ]

hundredHosts :: IO ()
hundredHosts = do
  let ep = resolve "serverspec" synthInventory synthPlan
  length (epJobs ep) @?= 100
  case validate ep >>= emitFor defaultServerspecScaffold defaultLayout of
    Left e -> assertFailure ("emit failed: " <> T.unpack e)
    Right outs -> do
      -- 100 host files + spec_helper.rb + Rakefile
      Map.size outs @?= 102
      forM_ (Map.toAscList outs) $ \(name, body) ->
        assertBool ("non-empty body: " <> name) (not (T.null body))
