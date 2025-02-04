module Lookup
  ( RST.PrdCnsToPol
  , RST.prdCnsToPol
  , lookupTerm
  , lookupCommand
  , lookupDataDecl
  , lookupTypeName
  , lookupXtorSig
  , lookupXtorSigLower
  , lookupXtorSigUpper
  , lookupXtorKind
  , lookupClassDecl
  , lookupMethodType
  , withTerm
    ) where

import Control.Monad.Except
import Control.Monad.Reader
import Data.List
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NE
import Data.Map (Map)
import Data.Map qualified as M

import Driver.Environment (Environment(..), emptyEnvironment)
import Errors
import Pretty.Pretty
import Pretty.Common ()
import Syntax.TST.Terms qualified as TST
import Syntax.TST.Types qualified as TST
import Syntax.TST.Program qualified as TST
import Syntax.RST.Program qualified as RST
import Syntax.RST.Types qualified as RST
import Syntax.RST.Types (PolarityRep(..), Polarity(..))
import Syntax.CST.Types (PrdCnsRep(..))
import Syntax.CST.Names
import Syntax.CST.Kinds (MonoKind)
import Loc ( Loc, defaultLoc )

---------------------------------------------------------------------------------
-- We define functions which work for every Monad which implements:
-- (1) MonadError Error
-- (2) MonadReader (Map ModuleName Environment ph, a)
---------------------------------------------------------------------------------

type EnvReader a m = (MonadError (NonEmpty Error) m, MonadReader (Map ModuleName Environment, a) m)

---------------------------------------------------------------------------------
-- Lookup Terms
---------------------------------------------------------------------------------

findFirstM :: forall a m res. EnvReader a m
           => (Environment -> Maybe res)
           -> Error
           -> m (ModuleName, res)
findFirstM f err = asks fst >>= \env -> go (M.toList env)
  where
    go :: [(ModuleName, Environment)] -> m (ModuleName, res)
    go [] = throwError (err NE.:| [])
    go ((mn,env):envs) =
      case f env of
        Just res -> pure (mn,res)
        Nothing -> go envs

-- | Lookup the term and the type of a term bound in the environment.
lookupTerm :: EnvReader a m => Loc -> PrdCnsRep pc -> FreeVarName -> m (TST.Term pc, TST.TypeScheme (RST.PrdCnsToPol pc))
lookupTerm loc PrdRep fv = do
  env <- asks fst
  let err = ErrOther $ SomeOtherError loc ("Unbound free producer variable " <> ppPrint fv <> " is not contained in environment.\n" <> ppPrint (M.keys env))
  let f env = case M.lookup fv (prdEnv env) of
                       Nothing -> Nothing
                       Just (res1,_,res2) -> Just (res1,res2)
  snd <$> findFirstM f err
lookupTerm loc CnsRep fv = do
  let err = ErrOther $ SomeOtherError loc ("Unbound free consumer variable " <> ppPrint fv <> " is not contained in environment.")
  let f env = case M.lookup fv (cnsEnv env) of
                       Nothing -> Nothing
                       Just (res1,_,res2) -> return (res1,res2)
  snd <$> findFirstM f err

---------------------------------------------------------------------------------
-- Lookup Commands
---------------------------------------------------------------------------------

-- | Lookup a command in the environment.
lookupCommand :: EnvReader a m => Loc -> FreeVarName -> m TST.Command
lookupCommand loc fv = do
  let err = ErrOther $ SomeOtherError loc ("Unbound free command variable " <> ppPrint fv <> " is not contained in environment.")
  let f env = case M.lookup fv (cmdEnv env) of
                     Nothing -> Nothing
                     Just (res, _) -> return res
  snd <$> findFirstM f err

---------------------------------------------------------------------------------
-- Lookup information about type declarations ------------------------------------------------------------------------------- | Find the type declaration belonging to a given Xtor Name.
lookupDataDecl :: EnvReader a m
               => Loc -> XtorName -> m TST.DataDecl
lookupDataDecl loc xt = do
  let containsXtor :: TST.XtorSig Pos -> Bool
      containsXtor sig = TST.sig_name sig == xt
  let typeContainsXtor :: TST.DataDecl -> Bool
      typeContainsXtor TST.NominalDecl { data_xtors } | or (containsXtor <$> fst data_xtors) = True
                                                      | otherwise = False
      typeContainsXtor TST.RefinementDecl { data_xtors } | or (containsXtor <$> fst data_xtors) = True
                                                         | otherwise = False
  let err = ErrOther $ SomeOtherError loc ("Constructor/Destructor " <> ppPrint xt <> " is not contained in program.")
  let f env = find typeContainsXtor (fmap snd (declEnv env))
  snd <$> findFirstM f err

-- | Find the type declaration belonging to a given TypeName.
lookupTypeName :: EnvReader a m
               => Loc -> RnTypeName -> m TST.DataDecl
lookupTypeName loc tn = do
  let err = ErrOther $ SomeOtherError loc ("Type name " <> unTypeName (rnTnName tn) <> " not found in environment")
  let findFun TST.NominalDecl{..} = data_name == tn
      findFun TST.RefinementDecl {..} = data_name == tn
  let f env = find findFun (fmap snd (declEnv env))
  snd <$> findFirstM f err

-- | Find the XtorSig belonging to a given XtorName.
lookupXtorSig :: EnvReader a m
              => Loc -> XtorName -> PolarityRep pol -> m (TST.XtorSig pol)
lookupXtorSig loc xtn PosRep = do
  decl <- lookupDataDecl loc xtn
  case find ( \TST.MkXtorSig{..} -> sig_name == xtn ) (fst (TST.data_xtors decl)) of
    Just xts -> pure xts
    Nothing -> throwOtherError loc ["XtorName " <> unXtorName xtn <> " not found in declaration of type " <> unTypeName (rnTnName (TST.data_name decl))]
lookupXtorSig loc xtn NegRep = do
  decl <- lookupDataDecl loc xtn
  case find ( \TST.MkXtorSig{..} -> sig_name == xtn ) (snd (TST.data_xtors decl)) of
    Just xts -> pure xts
    Nothing -> throwOtherError loc ["XtorName " <> unXtorName xtn <> " not found in declaration of type " <> unTypeName (rnTnName (TST.data_name decl))]


lookupXtorSigUpper :: EnvReader a m
                   => Loc -> XtorName -> m (TST.XtorSig Neg)
lookupXtorSigUpper loc xt = do
  decl <- lookupDataDecl loc xt
  case decl of
    TST.NominalDecl { } -> do
      throwOtherError loc ["lookupXtorSigUpper: Expected refinement type but found nominal type."]
    TST.RefinementDecl { data_xtors_refined } -> do
      case find ( \TST.MkXtorSig{..} -> sig_name == xt ) (snd data_xtors_refined) of
        Nothing -> throwOtherError loc ["lookupXtorSigUpper: Constructor/Destructor " <> ppPrint xt <> " not found"]
        Just sig -> pure sig



lookupXtorSigLower :: EnvReader a m
                   => Loc -> XtorName -> m (TST.XtorSig Pos)
lookupXtorSigLower loc xt = do
  decl <- lookupDataDecl loc xt
  case decl of
    TST.NominalDecl {} -> do
      throwOtherError loc ["lookupXtorSigLower: Expected refinement type but found nominal type."]
    TST.RefinementDecl { data_xtors_refined } -> do
      case find ( \TST.MkXtorSig{..} -> sig_name == xt ) (fst data_xtors_refined) of
        Nothing ->  throwOtherError loc ["lookupXtorSigLower: Constructor/Destructor " <> ppPrint xt <> " not found"]
        Just sig -> pure sig



-- | Find the class declaration for a classname.
lookupClassDecl :: EnvReader a m
               => Loc -> ClassName -> m RST.ClassDeclaration
lookupClassDecl loc cn = do
  let err = ErrOther $ SomeOtherError loc ("Undeclared class " <> ppPrint cn <> " is not contained in environment.")
  let f env = M.lookup cn (classEnv env)
  snd <$> findFirstM f err

-- | Find the type of a method in a given class declaration.
lookupMethodType :: EnvReader a m
               => Loc -> MethodName -> RST.ClassDeclaration -> PolarityRep pol -> m (RST.LinearContext pol)
lookupMethodType loc mn RST.MkClassDeclaration { classdecl_name, classdecl_methods } PosRep =
  case find ( \RST.MkMethodSig{..} -> msig_name == mn) (fst classdecl_methods) of
    Nothing -> throwOtherError loc ["Method " <> ppPrint mn <> " is not declared in class " <> ppPrint classdecl_name]
    Just msig -> pure $ RST.msig_args msig
lookupMethodType loc mn RST.MkClassDeclaration { classdecl_name, classdecl_methods } NegRep =
  case find ( \RST.MkMethodSig{..} -> msig_name == mn) (snd classdecl_methods) of
    Nothing -> throwOtherError loc ["Method " <> ppPrint mn <> " is not declared in class " <> ppPrint classdecl_name]
    Just msig -> pure $ RST.msig_args msig

lookupXtorKind :: EnvReader a m
             => XtorName -> m (MonoKind,[MonoKind])
lookupXtorKind xtorn = do
  let err = ErrOther $ SomeOtherError defaultLoc ("No Kinds for XTor " <> ppPrint xtorn)
  let f env = M.lookup xtorn (kindEnv env)
  snd <$> findFirstM f err


---------------------------------------------------------------------------------
-- Run a computation in a locally changed environment.
---------------------------------------------------------------------------------

withTerm :: forall a m b pc. EnvReader a m
         => ModuleName -> PrdCnsRep pc -> FreeVarName -> TST.Term pc -> Loc -> TST.TypeScheme (RST.PrdCnsToPol pc)
         -> (m b -> m b)
withTerm mn PrdRep fv tm loc tys action = do
  let modifyEnv :: Environment -> Environment
      modifyEnv env@MkEnvironment { prdEnv } =
        env { prdEnv = M.insert fv (tm,loc,tys) prdEnv }
  let modifyEnvMap :: (Map ModuleName Environment, a) -> (Map ModuleName Environment, a)
      modifyEnvMap (map, rest) =
        case M.lookup mn map of
          Nothing -> (M.insert mn (modifyEnv emptyEnvironment) map, rest)
          Just _  -> (M.adjust modifyEnv mn map, rest)
  local modifyEnvMap action
withTerm mn CnsRep fv tm loc tys action = do
  let modifyEnv :: Environment -> Environment
      modifyEnv env@MkEnvironment { cnsEnv } =
        env { cnsEnv = M.insert fv (tm,loc,tys) cnsEnv }
  let modifyEnvMap :: (Map ModuleName Environment, a) -> (Map ModuleName Environment, a)
      modifyEnvMap (map, rest) =
        case M.lookup mn map of
          Nothing ->  (M.insert mn (modifyEnv emptyEnvironment) map, rest)
          Just _  -> (M.adjust modifyEnv mn map, rest)
  local modifyEnvMap action

