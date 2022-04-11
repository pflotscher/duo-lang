module Translate.TranslateExamplesSpec ( spec ) where

import Control.Monad
import Test.Hspec

import Pretty.Pretty
import Pretty.Terms ()
import Pretty.Errors ()
import Pretty.Program ()
import Syntax.CST.Program qualified as CST
import Translate.Desugar
import Translate.EmbedCore
import Translate.Reparse
import Driver.Driver
import TestUtils

driverState :: DriverState
driverState = DriverState defaultInferenceOptions { infOptsLibPath = ["examples"]} mempty mempty

spec :: Spec
spec = do
    describe "Desugaring an entire program still typechecks" $ do
      examples <- runIO $ getAvailableExamples "examples/"
      forM_ examples $ \example -> do
        describe ("Desugaring the program in  " ++ example ++ " typechecks.") $ do
          decls <- runIO $ getTypecheckedDecls example defaultInferenceOptions { infOptsLibPath = ["examples"]}
          case decls of
            Left err -> it "Could not read in example " $ expectationFailure (ppPrintString err)
            Right decls -> do
              let desugaredDecls :: CST.Program = reparseProgram $ embedCoreProg $ desugarProgram decls
              res <- runIO $ inferProgramIO driverState desugaredDecls
              case res of
                Left err -> do
                  let msg = unlines [ "---------------------------------"
                                    , "Prettyprinted declarations:"
                                    , ""
                                    ,  ppPrintString (embedCoreProg $ desugarProgram decls)
                                    , ""
                                    , "Show instance of declarations:"
                                    , ""
                                    , show desugaredDecls
                                    , ""
                                    , "Error message:"
                                    , ""
                                    , ppPrintString err
                                    , "---------------------------------"
                                    ]
                  it "Could not load examples" $ expectationFailure msg
                Right _env -> return ()

