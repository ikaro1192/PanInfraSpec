module Unit.EmitSourceMapTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import PanInfraSpec.Emit (emitFor)
import PanInfraSpec.Emit.SourceMap
  ( EmitOptions (..)
  , defaultEmitOptions
  , formatDescribeSrcLoc
  , formatSrcComment
  , sourceComments
  , sourceLocInDescribe
  )
import PanInfraSpec.IR hiding (Assertion)
import qualified PanInfraSpec.IR as IR
import PanInfraSpec.Layout (defaultLayout)
import PanInfraSpec.Scaffold.Defaults.Serverspec (defaultServerspecScaffold)

tests :: TestTree
tests = testGroup "Emit.SourceMap"
  [ testCase "defaultEmitOptions has source comments enabled" $
      sourceComments defaultEmitOptions @?= True

  , testCase "defaultEmitOptions keeps describe-loc opt-in (off)" $
      sourceLocInDescribe defaultEmitOptions @?= False

  , testCase "formatDescribeSrcLoc [] yields Nothing" $
      formatDescribeSrcLoc [] @?= Nothing

  , testCase "formatDescribeSrcLoc renders a single location in parens" $
      formatDescribeSrcLoc [locA] @?= Just "(./plan.dhall:42:7)"

  , testCase "formatDescribeSrcLoc joins multiple locations with comma-space" $
      formatDescribeSrcLoc [locA, locB]
        @?= Just "(./plan.dhall:42:7, ./plan.dhall:55:9)"

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

  , testCase "describe omits secondary string when sourceLocInDescribe is off" $
      case emitWith defaultEmitOptions [withLoc commandUnameA locA] of
        Right out -> do
          assertBool "describe header without secondary string" $
            T.isInfixOf "describe command('uname -a') do" out
          assertBool "no secondary string sneaks in" $
            not (T.isInfixOf "describe command('uname -a')," out)
        Left e    -> assertFailure (T.unpack e)

  , testCase "describe gains secondary string when sourceLocInDescribe is on" $
      case emitWith optsWithDescribeLoc [withLoc commandUnameA locA] of
        Right out ->
          assertBool "describe header carries '(./plan.dhall:42:7)'" $
            T.isInfixOf "describe command('uname -a'), '(./plan.dhall:42:7)' do" out
        Left e    -> assertFailure (T.unpack e)

  , testCase "merged assertions produce comma-joined secondary string" $
      let merged =
            [ withLoc commandUnameA locA
            , withLoc (commandExitCode "uname -a" 0) locB
            ]
      in case emitWith optsWithDescribeLoc merged of
           Right out ->
             assertBool "describe header joins both source locations" $
               T.isInfixOf
                 "describe command('uname -a'), '(./plan.dhall:42:7, ./plan.dhall:55:9)' do"
                 out
           Left e    -> assertFailure (T.unpack e)

  , testCase "empty aSourceLocs leaves describe untouched even when flag is on" $
      case emitWith optsWithDescribeLoc [commandUnameA] of
        Right out -> do
          assertBool "describe header has no secondary string" $
            T.isInfixOf "describe command('uname -a') do" out
          assertBool "no comma after the resource" $
            not (T.isInfixOf "describe command('uname -a')," out)
        Left e    -> assertFailure (T.unpack e)
  ]

optsWithDescribeLoc :: EmitOptions
optsWithDescribeLoc = defaultEmitOptions { sourceLocInDescribe = True }

withLoc :: IR.Assertion -> SourceLoc -> IR.Assertion
withLoc a loc = a { aSourceLocs = [loc] }

commandUnameA :: IR.Assertion
commandUnameA = IR.mkAssertion "command" "uname -a"
  (Map.fromList [("exit-status", AVNat 0)])
  Nothing

commandExitCode :: Text -> Integer -> IR.Assertion
commandExitCode cmd code = IR.mkAssertion "command" cmd
  (Map.fromList [("exit-status", AVNat (fromInteger code))])
  Nothing

emitWith :: EmitOptions -> [IR.Assertion] -> Either Text Text
emitWith opts asserts =
  let node = Node
        { hostname         = "h"
        , ip               = Nothing
        , role             = Role "Web"
        , tags             = []
        , customAttributes = []
        }
      ep = ExecutionPlan "serverspec" [Job node asserts]
  in case emitFor defaultServerspecScaffold defaultLayout ep opts of
       Left e     -> Left e
       Right outs -> case Map.lookup "h_spec.rb" outs of
         Just t  -> Right t
         Nothing -> Left "missing h_spec.rb"

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
