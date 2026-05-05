module Unit.EmitSourceMapTest (tests) where

import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Emit.SourceMap (defaultEmitOptions, formatSrcComment, sourceComments)
import PanInfraSpec.IR.SourceLoc (SourceLoc (..))

tests :: TestTree
tests = testGroup "Emit.SourceMap"
  [ testCase "defaultEmitOptions has source comments enabled" $
      sourceComments defaultEmitOptions @?= True

  , testCase "formatSrcComment [] yields no lines" $
      formatSrcComment [] @?= []

  , testCase "formatSrcComment renders one '# src:' line per location" $
      formatSrcComment [locA, locB]
        @?= [ "# src: ./plan.dhall:42:7 — file_owner \"/etc/nginx/nginx.conf\" \"root\""
            , "# src: ./plan.dhall:55:9 — file_mode \"/etc/nginx/nginx.conf\" 0o644"
            ]

  , testCase "multi-line slText is collapsed to a single line" $
      formatSrcComment [multilineLoc]
        @?= [ "# src: ./plan.dhall:10:1 — file_owner \"/etc/nginx/nginx.conf\" \"root\"" ]

  , testCase "long slText is truncated with an ellipsis" $
      case formatSrcComment [longLoc] of
        [out] -> do
          let (header, tail') = T.breakOn " — " out
          header @?= "# src: ./plan.dhall:1:1"
          assertBool "ends in an ellipsis" (T.isSuffixOf "…" tail')
          assertBool "stays under the rendered budget" (T.length tail' <= 84)
        outs  -> assertFailure ("expected one line, got " <> show outs)
  ]

locA :: SourceLoc
locA = SourceLoc
  { slFile      = "./plan.dhall"
  , slStartLine = 42
  , slStartCol  = 7
  , slEndLine   = 42
  , slEndCol    = 50
  , slText      = "file_owner \"/etc/nginx/nginx.conf\" \"root\""
  }

locB :: SourceLoc
locB = SourceLoc
  { slFile      = "./plan.dhall"
  , slStartLine = 55
  , slStartCol  = 9
  , slEndLine   = 55
  , slEndCol    = 50
  , slText      = "file_mode \"/etc/nginx/nginx.conf\" 0o644"
  }

multilineLoc :: SourceLoc
multilineLoc = SourceLoc
  { slFile      = "./plan.dhall"
  , slStartLine = 10
  , slStartCol  = 1
  , slEndLine   = 12
  , slEndCol    = 5
  , slText      = "file_owner\n  \"/etc/nginx/nginx.conf\"\n  \"root\""
  }

longLoc :: SourceLoc
longLoc = SourceLoc
  { slFile      = "./plan.dhall"
  , slStartLine = 1
  , slStartCol  = 1
  , slEndLine   = 1
  , slEndCol    = 200
  , slText      = T.replicate 200 "x"
  }
