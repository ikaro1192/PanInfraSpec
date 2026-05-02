module Main (main) where

import Options.Applicative (execParser)
import System.Exit (exitWith)

import PanInfraSpec.CLI (parserInfo, run)

main :: IO ()
main = execParser parserInfo >>= run >>= exitWith
