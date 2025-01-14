module Spec.LocallyClosed where

import Control.Monad (forM_)
import Data.Text qualified as T
import Data.List.NonEmpty (NonEmpty)
import Test.Hspec

import Pretty.Pretty ( ppPrintString )
import Pretty.Errors ()
import Syntax.Core.Terms (Pattern(..))
import Syntax.TST.Terms ( InstanceCase (instancecase_pat), Term, termLocallyClosed, instanceCaseLocallyClosed)
import Syntax.TST.Program qualified as TST
import Syntax.CST.Names
import Syntax.CST.Types (PrdCns(..), PrdCnsRep(..))
import Errors ( Error )
import Data.Either (isRight)
import Utils (moduleNameToFullPath)

type Reason = String

pendingFiles :: [(ModuleName, Reason)]
pendingFiles = []

getProducers :: TST.Module -> [(FreeVarName, Term Prd)]
getProducers TST.MkModule { mod_decls } = go mod_decls []
  where
    go :: [TST.Declaration] -> [(FreeVarName, Term Prd)] -> [(FreeVarName, Term Prd)]
    go [] acc = acc
    go ((TST.PrdCnsDecl PrdRep (TST.MkPrdCnsDeclaration _ _ PrdRep _ fv _ tm)):rest) acc = go rest ((fv,tm):acc)
    go (_:rest) acc = go rest acc

getInstanceCases :: TST.Module -> [InstanceCase]
getInstanceCases TST.MkModule { mod_decls } = go mod_decls []
  where
    go :: [TST.Declaration] -> [InstanceCase] -> [InstanceCase]
    go [] acc = acc
    go ((TST.InstanceDecl (TST.MkInstanceDeclaration _ _ _ _ _ cases)):rest) acc = go rest (cases++acc)
    go (_:rest) acc = go rest acc

spec :: [((FilePath, ModuleName), Either (NonEmpty Error) TST.Module)] -> Spec
spec examples = do
  describe "All examples are locally closed." $ do
    forM_ examples $ \((example, mn), eitherEnv) -> do
      let fullName = moduleNameToFullPath mn example
      case mn `lookup` pendingFiles of
        Just reason -> it "" $ pendingWith $ "Could check local closure of file " ++ fullName ++ "\nReason: " ++ reason
        Nothing     -> describe ("Examples in " ++ fullName ++ " are locally closed") $ do
          case eitherEnv of
            Left err -> it "Could not load examples." $ expectationFailure (ppPrintString err)
            Right env -> do
              forM_ (getProducers env) $ \(name,term) -> do
                it (T.unpack (unFreeVarName name) ++ " does not contain dangling deBruijn indizes") $
                  termLocallyClosed term `shouldSatisfy` isRight
              forM_ (getInstanceCases env) $ \instance_case -> do
                it (T.unpack (unXtorName $ (\(XtorPat _ xt _) -> xt) $ instancecase_pat instance_case) ++ " does not contain dangling deBruijn indizes") $
                  instanceCaseLocallyClosed instance_case `shouldSatisfy` isRight

