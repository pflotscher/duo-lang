module Lookup
  ( PrdCnsToPol
  , prdCnsToPol
  , lookupSTerm
  , lookupATerm
  , lookupDataDecl
  , lookupXtorSig
  , withSTerm
  , withATerm
  ) where

import Control.Monad.Except
import Control.Monad.Reader
import Data.List
import qualified Data.Map as M


import Errors
import Pretty.Pretty
import Syntax.CommonTerm
import Syntax.STerms
import Syntax.ATerms
import Syntax.Types
import Syntax.Program

---------------------------------------------------------------------------------
-- We define functions which work for every Monad which implements:
-- (1) MonadError Error
-- (2) MonadReader (Environment bs, a)
---------------------------------------------------------------------------------

type EnvReader bs a m = (MonadError Error m, MonadReader (Environment bs, a) m)


-- | We map producer terms to positive types, and consumer terms to negative types.
type family PrdCnsToPol (pc :: PrdCns) :: Polarity where
  PrdCnsToPol Prd = Pos
  PrdCnsToPol Cns = Neg

prdCnsToPol :: PrdCnsRep pc -> PolarityRep (PrdCnsToPol pc)
prdCnsToPol PrdRep = PosRep
prdCnsToPol CnsRep = NegRep

---------------------------------------------------------------------------------
-- Lookup Terms
---------------------------------------------------------------------------------

-- | Lookup the term and the type of a asymmetric term bound in the environment.
lookupATerm :: EnvReader bs a m
            => FreeVarName -> m (ATerm () bs, TypeScheme Pos)
lookupATerm fv = do
  env <- asks fst
  case M.lookup fv (defEnv env) of
    Nothing -> throwOtherError ["Unbound free variable " <> ppPrint fv <> " not contained in the environment."]
    Just res -> return res

-- | Lookup the term and the type of a symmetric term bound in the environment.
lookupSTerm :: EnvReader bs a m
            => PrdCnsRep pc -> FreeVarName -> m (STerm pc () bs, TypeScheme (PrdCnsToPol pc))
lookupSTerm PrdRep fv = do
  env <- asks fst
  case M.lookup fv (prdEnv env) of
    Nothing -> throwOtherError ["Unbound free variable " <> ppPrint fv <> " is not contained in environment."]
    Just res -> return res
lookupSTerm CnsRep fv = do
  env <- asks fst
  case M.lookup fv (cnsEnv env) of
    Nothing -> throwOtherError ["Unbound free variable " <> ppPrint fv <> " is not contained in the environment."]
    Just res -> return res

---------------------------------------------------------------------------------
-- Lookup information about type declarations
---------------------------------------------------------------------------------

-- | Find the type declaration belonging to a given Xtor Name.
lookupDataDecl :: EnvReader bs a m
               => XtorName -> m DataDecl
lookupDataDecl xt = do
  let containsXtor :: XtorSig Pos -> Bool
      containsXtor sig = sig_name sig == xt
  let typeContainsXtor :: DataDecl -> Bool
      typeContainsXtor NominalDecl { data_xtors } | or (containsXtor <$> data_xtors PosRep) = True
                                                  | otherwise = False
  env <- declEnv <$> asks fst
  case find typeContainsXtor env of
    Nothing -> throwOtherError ["Constructor/Destructor " <> ppPrint xt <> " is not contained in program."]
    Just decl -> return decl

-- | Find the XtorSig belonging to a given XtorName.
lookupXtorSig :: EnvReader bs a m
              => XtorName -> PolarityRep pol -> m (XtorSig pol)
lookupXtorSig xtn pol = do
  decl <- lookupDataDecl xtn
  case find ( \MkXtorSig{..} -> sig_name == xtn ) (data_xtors decl pol) of
    Just xts -> return xts
    Nothing -> throwOtherError ["XtorName " <> unXtorName xtn <> " not found in declaration of type " <> unTypeName (data_name decl)]

---------------------------------------------------------------------------------
-- Run a computation in a locally changed environment.
---------------------------------------------------------------------------------

withSTerm :: EnvReader bs a m
          => PrdCnsRep pc -> FreeVarName -> STerm pc () bs -> TypeScheme (PrdCnsToPol pc)
          -> (m b -> m b)
withSTerm PrdRep fv tm tys m = do
  let modifyEnv (env@Environment { prdEnv }, rest) =
        (env { prdEnv = M.insert fv (tm,tys) prdEnv }, rest)
  local modifyEnv m
withSTerm CnsRep fv tm tys m = do
  let modifyEnv (env@Environment { cnsEnv }, rest) =
        (env { cnsEnv = M.insert fv (tm,tys) cnsEnv }, rest)
  local modifyEnv m

withATerm :: EnvReader bs a m
        => FreeVarName -> ATerm () bs -> TypeScheme Pos
        -> (m b -> m b)
withATerm fv tm tys m = do
  let modifyEnv (env@Environment { defEnv }, rest) =
        (env { defEnv = M.insert fv (tm,tys) defEnv }, rest)
  local modifyEnv m