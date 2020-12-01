module GenerateConstraints
  ( generateConstraints
  , typedTermToType
  , termPrdCns
  ) where

import Control.Monad.State
import Control.Monad.Except

import Syntax.Terms
import Syntax.Types
import Utils
import Eval

{-
Constraint generation is split in two phases:

  1) The term is annotated with fresh unification variables
  2) The term is traversed and constraints are collected

This seperation is only possible because in our system, there is a 1-to-1 correspondence between program variables
and unifcation variables. Thus, during the actual constraint generation, we don't ever have to come up with new
unifcation variables.
-}

termPrdCns :: Term Prd a -> PrdCns
termPrdCns (XtorCall pc _ _)     = pc
termPrdCns (Match pc _)          = pc
termPrdCns (MuAbs pc _ _)       = pc
termPrdCns (BoundVar pc _)       = pc
termPrdCns (FreeVar pc _ _)      = pc

-------------------------------------------------------------------------------------
-- Phase 1: Term annotation
-------------------------------------------------------------------------------------

type GenerateM a = StateT Int (Except String) a

freshVars :: Int -> GenerateM [(UVar, Term Prd UVar)]
freshVars k = do
  n <- get
  modify (+k)
  return [(uv, FreeVar Prd ("x" ++ show i) uv) | i <- [n..n+k-1], let uv = MkUVar i]

annotateTerm :: Term Prd () -> GenerateM (Term Prd UVar)
annotateTerm (FreeVar _ v _)     = throwError $ "Unknown free variable: \"" ++ v ++ "\""
annotateTerm (BoundVar idx pc) = return (BoundVar idx pc)
annotateTerm (XtorCall s xt (MkXtorArgs prdArgs cnsArgs)) = do
  prdArgs' <- mapM annotateTerm prdArgs
  cnsArgs' <- mapM annotateTerm cnsArgs
  return (XtorCall s xt (MkXtorArgs prdArgs' cnsArgs'))
annotateTerm (Match s cases) =
  Match s <$> forM cases (\(MkCase xt (Twice prds cnss) cmd) -> do
    (prdUVars, prdTerms) <- unzip <$> freshVars (length prds)
    (cnsUVars, cnsTerms) <- unzip <$> freshVars (length cnss)
    cmd' <- annotateCommand cmd
    return (MkCase xt (Twice prdUVars cnsUVars) (commandOpening (MkXtorArgs prdTerms cnsTerms) cmd')))
annotateTerm (MuAbs pc _ cmd) = do
  (uv, freeVar) <- head <$> freshVars 1
  cmd' <- annotateCommand cmd
  return (MuAbs pc uv (commandOpeningSingle pc freeVar cmd'))

annotateCommand :: Command () -> GenerateM (Command UVar)
annotateCommand Done = return Done
annotateCommand (Print t) = Print <$> (annotateTerm t)
annotateCommand (Apply t1 t2) = do
  t1' <- annotateTerm t1
  t2' <- annotateTerm t2
  return (Apply t1' t2')

---------------------------------------------------------------------------------------------
-- Phase 2: Constraint collection
---------------------------------------------------------------------------------------------

-- only defined for fully opened terms, i.e. no de brujin indices left
typedTermToType :: Term Prd UVar -> SimpleType
typedTermToType (FreeVar _ _ t)        = TyVar t
typedTermToType (BoundVar _ _)     = error "typedTermToType: found dangling bound variable"
typedTermToType (XtorCall pc xt (MkXtorArgs prdargs cnsargs)) =
  SimpleType (case pc of Prd -> Data; Cns -> Codata) [(xt, Twice (typedTermToType <$> prdargs) (typedTermToType <$> cnsargs))]
typedTermToType (Match pc cases)      =
  SimpleType (case pc of Prd -> Codata; Cns -> Data) (map getCaseType cases)
  where
    getCaseType (MkCase xt types _) = (xt, (fmap . fmap) TyVar types)
typedTermToType (MuAbs _ t _)        = TyVar t

getConstraintsTerm :: Term Prd UVar -> [Constraint]
getConstraintsTerm (BoundVar _ _) = error "getConstraintsTerm:  found dangling bound variable"
getConstraintsTerm (FreeVar _ _ _)    = []
getConstraintsTerm (XtorCall _ _ (MkXtorArgs prdargs cnsargs)) =
  concat $ mergeTwice (++) $ Twice (getConstraintsTerm <$> prdargs) (getConstraintsTerm <$> cnsargs)
getConstraintsTerm (Match _ cases) = concat $ map (\(MkCase _ _ cmd) -> getConstraintsCommand cmd) cases
getConstraintsTerm (MuAbs _ _ cmd) = getConstraintsCommand cmd

getConstraintsCommand :: Command UVar -> [Constraint]
getConstraintsCommand Done = []
getConstraintsCommand (Print t) = getConstraintsTerm t
getConstraintsCommand (Apply t1 t2) = newCs : (getConstraintsTerm t1 ++ getConstraintsTerm t2)
  where newCs = SubType (typedTermToType t1) (typedTermToType t2)

generateConstraints :: Term Prd () -> Either Error (Term Prd UVar, [Constraint], [UVar])
generateConstraints t0 =
  case runExcept (runStateT (annotateTerm t0) 0) of
    Right (t1, numVars) -> Right (t1, getConstraintsTerm t1, MkUVar <$> [0..numVars-1])
    Left err            -> Left $ GenConstraintsError err

