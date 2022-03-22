module Translate.FocusingSpec (spec) where

import Control.Monad
import Test.Hspec
import TestUtils
import Pretty.Pretty
import Pretty.Program ()

import Driver.Driver
import Translate.Desugar
import Syntax.Common
import Syntax.AST.Program
import Translate.Focusing
import Translate.Reparse


driverState :: DriverState
driverState = DriverState defaultInferenceOptions { infOptsLibPath = ["examples"]} mempty

testHelper :: FilePath -> EvaluationOrder -> SpecWith ()
testHelper example cbx = describe (show cbx ++ " Focusing the program in  " ++ example ++ " typechecks.") $ do
  decls <- runIO $ getTypecheckedDecls example defaultInferenceOptions { infOptsLibPath = ["examples"]}
  case decls of
    Left err -> it "Could not read in example " $ expectationFailure (ppPrintString err)
    Right decls -> do
      let focusedDecls :: Program Parsed = reparseProgram $ focusProgram cbx (desugarProgram decls)
      res <- runIO $ inferProgramIO' driverState focusedDecls
      case res of
        Left err -> do
           let msg = unlines [ "---------------------------------"
                             , "Prettyprinted declarations:"
                             , ""
                             ,  ppPrintString focusedDecls
                             , ""
                             , "Show instance of declarations:"
                             , ""
                             , show focusedDecls
                             , ""
                             , "Error message:"
                             , ""
                             , ppPrintString err
                             , "---------------------------------"
                             ]
           it "Could not load examples" $ expectationFailure msg
        Right _env -> return ()

spec :: Spec
spec = do
    describe "Focusing an entire program still typechecks" $ do
      examples <- runIO $ getAvailableExamples "examples/"
      forM_ examples $ \example -> do
        testHelper example CBV
        testHelper example CBN
