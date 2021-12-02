module Translate.Reparse
  ( reparseTerm
  , reparseCommand
  , reparseDecl
  , reparseProgram
  ) where

import Control.Monad.State
import Data.Bifunctor
import Data.Text qualified as T

import Syntax.CommonTerm
import Syntax.Program
import Syntax.Terms
import Utils

---------------------------------------------------------------------------------
-- CreateNames Monad
---------------------------------------------------------------------------------

type CreateNameM a = State ([FreeVarName],[FreeVarName]) a

names :: ([FreeVarName], [FreeVarName])
names =  ((\y -> "x" <> T.pack (show y)) <$> [(1 :: Int)..]
         ,(\y -> "k" <> T.pack (show y)) <$> [(1 :: Int)..])

fresh :: PrdCns -> CreateNameM (Maybe FreeVarName)
fresh Prd = do
  var <- gets (head . fst)
  modify (first tail)
  pure (Just var)
fresh Cns = do
  var  <- gets (head . snd)
  modify (second tail)
  pure (Just var)

createNamesPCTerm :: PrdCnsTerm ext -> CreateNameM (PrdCnsTerm Parsed)
createNamesPCTerm (PrdTerm tm) = PrdTerm <$> createNamesTerm tm
createNamesPCTerm (CnsTerm tm) = CnsTerm <$> createNamesTerm tm

createNamesTerm :: Term pc ext -> CreateNameM (Term pc Parsed)
createNamesTerm (BoundVar _ pc idx) = return $ BoundVar defaultLoc pc idx
createNamesTerm (FreeVar _ pc nm)   = return $ FreeVar defaultLoc pc nm
createNamesTerm (XtorCall _ pc xt subst) = do
  subst' <- sequence $ createNamesPCTerm <$> subst
  return $ XtorCall defaultLoc pc xt subst'
createNamesTerm (XMatch _ pc ns cases) = do
  cases' <- sequence $ createNamesCmdCase <$> cases
  return $ XMatch defaultLoc pc ns cases'
createNamesTerm (MuAbs _ pc _ cmd) = do
  cmd' <- createNamesCommand cmd
  var <- fresh (case pc of PrdRep -> Cns; CnsRep -> Prd)
  return $ MuAbs defaultLoc pc var cmd'
createNamesTerm (Dtor _ xt e args) = do
  e' <- createNamesTerm e
  args' <- sequence (createNamesPCTerm <$> args)
  return $ Dtor defaultLoc xt e' args'
createNamesTerm (Match _ ns e cases) = do
  e' <- createNamesTerm e
  cases' <- sequence (createNamesTermCase <$> cases)
  return $ Match defaultLoc ns e' cases'
createNamesTerm (Comatch _ ns cases) = do
  cases' <- sequence (createNamesTermCaseI <$> cases)
  return $ Comatch defaultLoc ns cases'

createNamesCommand :: Command ext -> CreateNameM (Command Parsed)
createNamesCommand (Done _) = return $ Done defaultLoc
createNamesCommand (Apply _ prd cns) = do
  prd' <- createNamesTerm prd
  cns' <- createNamesTerm cns
  return (Apply defaultLoc prd' cns')
createNamesCommand (Print _ prd) = createNamesTerm prd >>= \prd' -> return (Print defaultLoc prd')

createNamesCmdCase :: CmdCase ext -> CreateNameM (CmdCase Parsed)
createNamesCmdCase (MkCmdCase { cmdcase_name, cmdcase_args, cmdcase_cmd }) = do
  cmd' <- createNamesCommand cmdcase_cmd
  args <- sequence $ (\(pc,_) -> (fresh pc >>= \v -> return (pc,v))) <$> cmdcase_args
  return $ MkCmdCase defaultLoc cmdcase_name args cmd'

createNamesTermCase :: TermCase ext -> CreateNameM (TermCase Parsed)
createNamesTermCase (MkTermCase _ xt args e) = do
  e' <- createNamesTerm e
  args' <- sequence $ (\(pc,_) -> (fresh pc >>= \v -> return (pc,v))) <$> args
  return $ MkTermCase defaultLoc xt args' e'

createNamesTermCaseI :: TermCaseI ext -> CreateNameM (TermCaseI Parsed)
createNamesTermCaseI (MkTermCaseI _ xt args e) = do
  e' <- createNamesTerm e
  args' <- sequence $ (\(pc,_) -> (fresh pc >>= \v -> return (pc,v))) <$> args
  return $ MkTermCaseI defaultLoc xt args' e'

---------------------------------------------------------------------------------
-- CreateNames Monad
---------------------------------------------------------------------------------

reparseTerm :: Term pc ext -> Term pc Parsed
reparseTerm tm = evalState (createNamesTerm tm) names

reparseCommand :: Command ext -> Command Parsed
reparseCommand cmd = evalState (createNamesCommand cmd) names

reparseDecl :: Declaration ext -> Declaration Parsed
reparseDecl (PrdCnsDecl _ rep isRec fv ts tm) = PrdCnsDecl defaultLoc rep isRec fv ts (reparseTerm tm)
reparseDecl (CmdDecl _ fv cmd) = CmdDecl defaultLoc fv (reparseCommand cmd)
reparseDecl (DataDecl _ decl) = DataDecl defaultLoc decl
reparseDecl (ImportDecl _ mn) = ImportDecl defaultLoc mn
reparseDecl (SetDecl _ txt) = SetDecl defaultLoc txt
reparseDecl ParseErrorDecl = ParseErrorDecl

reparseProgram :: Program ext -> Program Parsed
reparseProgram = fmap reparseDecl