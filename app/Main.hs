{-# LANGUAGE TemplateHaskell #-}
module Main where

import Data.Text qualified as T
import Data.Version (showVersion)
import GitHash (tGitInfoCwd, giHash, giBranch)

import Options (Options(..), parseOptions)
import Compile (runCompile)
import Deps (runDeps)
import Repl.Run (runRepl)
import LSP.LSP (runLSP)
import Paths_dualsub (version)
import Syntax.Common
import Utils (trimStr)

main :: IO ()
main = do
    opts <- parseOptions
    dispatch opts

dispatch :: Options -> IO ()
dispatch OptRepl         = runRepl
dispatch (OptLSP log)    = runLSP log
dispatch (OptCompile fp) = runCompile (MkModuleName (T.pack (trimStr fp)))
dispatch (OptDeps fp)    = runDeps (MkModuleName (T.pack (trimStr fp)))
dispatch OptVersion      = printVersion

printVersion :: IO ()
printVersion = do
    let gi = $$tGitInfoCwd
    putStrLn $ "DualSub Version: " <> showVersion version
    putStrLn $ "Git Commit: " <> giHash gi
    putStrLn $ "Git Branch: " <> giBranch gi