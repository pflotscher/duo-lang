module TypeInference.ExamplesSpec ( spec ) where

import Test.Hspec
import Control.Monad (forM_)

import Data.Either( isRight, isLeft )
import TestUtils

-- | Typecheck the programs in the toplevel "examples/" subfolder.
spec :: ([FilePath], [FilePath]) -> Spec
spec (examples, counterExamples) = do
  describe "All the programs in the toplevel \"examples/\" folder typecheck." $ do
    forM_ examples $ \example -> do
      env <- runIO $ getEnvironment example
      it ("The file " ++ example ++ " typechecks.") $ do
        env `shouldSatisfy` isRight

  describe "All the programs in the \"test/counterexamples/\" folder can be parsed." $ do
    forM_ counterExamples $ \example -> do
      describe ("The counterexample " ++ example ++ " can be parsed") $ do
        parsed <- runIO $ getParsedDeclarations example
        it "Can be parsed" $ parsed `shouldSatisfy` isRight

  describe "All the programs in the \"test/counterexamples/\" folder don't typecheck." $ do
    forM_ counterExamples $ \example -> do
      describe ("The counterexample " ++ example ++ " doesn't typecheck.") $ do
        env <- runIO $ getEnvironment example
        it "Doesn't typecheck" $  env `shouldSatisfy` isLeft