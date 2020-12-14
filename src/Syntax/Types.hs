module Syntax.Types where

import Data.List (nub)

import Syntax.Terms
import Utils

------------------------------------------------------------------------------
-- Type syntax
------------------------------------------------------------------------------


data TypeName = MkTypeName { unTypeName :: String } deriving (Eq, Show)

data DataCodata
  = Data
  | Codata
  deriving (Eq, Show, Ord)

newtype UVar = MkUVar {uvar_id :: Int} deriving (Eq,Ord)

instance Show UVar where
  show (MkUVar i) = "U" ++ show i

switchPrdCns :: PrdCns -> PrdCns
switchPrdCns Cns = Prd
switchPrdCns Prd = Cns

applyVariance :: DataCodata -> PrdCns -> (PrdCns -> PrdCns)
applyVariance Data Prd = id
applyVariance Data Cns = switchPrdCns
applyVariance Codata Prd = switchPrdCns
applyVariance Codata Cns = id

data XtorSig a = MkXtorSig { sig_name :: XtorName, sig_args :: Twice [a] }
  deriving (Show, Eq)

data SimpleType =
    TyVar UVar
  | SimpleType DataCodata [XtorSig SimpleType]
  | NominalType TypeName

  deriving (Show,Eq)

data Constraint = SubType SimpleType SimpleType deriving (Eq, Show)

-- free type variables
newtype TVar = MkTVar { tvar_name :: String } deriving (Eq, Ord, Show)

alphaRenameTVar :: [TVar] -> TVar -> TVar
alphaRenameTVar tvs tv
  | tv `elem` tvs = head [newtv | n <- [(0 :: Integer)..], let newtv = MkTVar (tvar_name tv ++ show n), not (newtv `elem` tvs)]
  | otherwise = tv

-- bound type variables (used in recursive types)
newtype RVar = MkRVar { rvar_name :: String } deriving (Eq, Ord, Show)

data TargetType
  = TTyUnion [TargetType]
  | TTyInter [TargetType]
  | TTyTVar TVar
  | TTyRVar RVar
  | TTyRec RVar TargetType
  | TTySimple DataCodata [XtorSig TargetType]
  | TTyNominal TypeName
  deriving (Eq,Show)

-- replaces all free type variables in the type, so that they don't intersect with the given type variables
alphaRenameTargetType :: [TVar] -> TargetType -> TargetType
alphaRenameTargetType tvs (TTyTVar tv)   = TTyTVar (alphaRenameTVar tvs tv)
alphaRenameTargetType _   (TTyRVar rv)   = TTyRVar rv
alphaRenameTargetType tvs (TTyUnion tys) = TTyUnion (map (alphaRenameTargetType tvs) tys)
alphaRenameTargetType tvs (TTyInter tys) = TTyInter (map (alphaRenameTargetType tvs) tys)
alphaRenameTargetType tvs (TTyRec rv ty) = TTyRec rv (alphaRenameTargetType tvs ty)
alphaRenameTargetType _ (TTyNominal tn) = TTyNominal tn
alphaRenameTargetType tvs (TTySimple s sigs) = TTySimple s $ map renameXtorSig  sigs
  where
    renameXtorSig (MkXtorSig xt args) = MkXtorSig xt (twiceMap (map (alphaRenameTargetType tvs)) (map (alphaRenameTargetType tvs)) args)

data TypeScheme = TypeScheme { ts_vars :: [TVar], ts_monotype :: TargetType } deriving (Show, Eq)

-- renames free variables of a type scheme, so that they don't intersect with the given list
alphaRenameTypeScheme :: [TVar] -> TypeScheme -> TypeScheme
alphaRenameTypeScheme tvs (TypeScheme tvs' ty) = TypeScheme (map (alphaRenameTVar tvs) tvs') (alphaRenameTargetType tvs ty)

unionOrInter :: PrdCns -> [TargetType] -> TargetType
unionOrInter _ [t] = t
unionOrInter Prd tys = TTyUnion tys
unionOrInter Cns tys = TTyInter tys

freeTypeVars' :: TargetType -> [TVar]
freeTypeVars' (TTyTVar tv) = [tv]
freeTypeVars' (TTyRVar _)  = []
freeTypeVars' (TTyUnion ts) = concat $ map freeTypeVars' ts
freeTypeVars' (TTyInter ts) = concat $ map freeTypeVars' ts
freeTypeVars' (TTyRec _ t)  = freeTypeVars' t
freeTypeVars' (TTyNominal _) = []
freeTypeVars' (TTySimple _ xtors) = concat (map freeTypeVarsXtorSig  xtors)
  where
    freeTypeVarsXtorSig (MkXtorSig _ (Twice prdTypes cnsTypes)) =
      concat (map freeTypeVars' prdTypes ++ map freeTypeVars' cnsTypes)

freeTypeVars :: TargetType -> [TVar]
freeTypeVars = nub . freeTypeVars'

-- generalizes over all free type variables of a type
generalize :: TargetType -> TypeScheme
generalize ty = TypeScheme (freeTypeVars ty) ty

------------------------------------------------------------------------------
-- Data Type declarations
------------------------------------------------------------------------------

data DataDecl = NominalDecl
  { data_name :: TypeName
  , data_polarity :: DataCodata
  , data_xtors :: [XtorSig SimpleType]
  }
  deriving (Show, Eq)
