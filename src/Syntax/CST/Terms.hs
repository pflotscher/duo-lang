module Syntax.CST.Terms where

import Syntax.CST.Names ( FreeVarName, XtorName, PrimName )
import Loc ( HasLoc(..), Loc )
import Syntax.CST.Types (Typ)

--------------------------------------------------------------------------------------------
-- Substitutions 
--------------------------------------------------------------------------------------------

data TermOrStar where
    ToSTerm :: Term -> TermOrStar
    ToSStar :: TermOrStar

deriving instance Show TermOrStar
deriving instance Eq TermOrStar

newtype Substitution =
  MkSubstitution { unSubstitution :: [Term] }

deriving instance Show Substitution
deriving instance Eq Substitution

newtype SubstitutionI =
  MkSubstitutionI { unSubstitutionI :: [TermOrStar] }

deriving instance Show SubstitutionI
deriving instance Eq SubstitutionI

--------------------------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------------------------

data Pattern where
  PatXtor     :: Loc -> XtorName -> [Pattern] -> Pattern
  PatVar      :: Loc -> FreeVarName -> Pattern
  PatStar     :: Loc -> Pattern
  PatWildcard :: Loc -> Pattern

deriving instance Show Pattern
deriving instance Eq Pattern

instance HasLoc Pattern where
  getLoc (PatXtor loc _ _) = loc
  getLoc (PatVar loc _) = loc
  getLoc (PatStar loc) = loc
  getLoc (PatWildcard loc) = loc

--------------------------------------------------------------------------------------------
-- Cases/Cocases
--------------------------------------------------------------------------------------------

data TermCase  = MkTermCase
  { tmcase_loc  :: Loc
  , tmcase_pat  :: Pattern
  , tmcase_term :: Term
  }

deriving instance Show TermCase
deriving instance Eq TermCase

instance HasLoc TermCase where
  getLoc tc = tmcase_loc tc

--------------------------------------------------------------------------------------------
-- Terms
--------------------------------------------------------------------------------------------

data NominalStructural where
  Nominal :: NominalStructural
  Structural :: NominalStructural
  Refinement :: NominalStructural
  deriving (Eq, Ord, Show)

data Term where
    PrimTerm :: Loc -> PrimName -> Substitution -> Term 
    Var :: Loc -> FreeVarName -> Term
    Xtor :: Loc -> XtorName  -> Maybe Typ -> SubstitutionI -> Term
    Semi :: Loc -> XtorName -> SubstitutionI -> Term -> Term
    Case :: Loc -> [TermCase] -> Term
    CaseOf :: Loc -> Term -> [TermCase] -> Term
    Cocase :: Loc -> [TermCase] -> Term
    CocaseOf :: Loc -> Term -> [TermCase] -> Term
    MuAbs :: Loc -> FreeVarName -> Term -> Term
    Dtor :: Loc -> XtorName -> Term -> SubstitutionI -> Term
    PrimLitI64 :: Loc -> Integer -> Term
    PrimLitF64 :: Loc -> Double -> Term
    PrimLitChar :: Loc -> Char -> Term
    PrimLitString :: Loc -> String -> Term
    NatLit :: Loc -> NominalStructural -> Int -> Term
    TermParens :: Loc -> Term -> Term
    FunApp :: Loc -> Term -> Term -> Term
    Lambda :: Loc -> FreeVarName -> Term -> Term
    CoLambda :: Loc -> FreeVarName -> Term -> Term
    Apply :: Loc -> Term -> Term -> Term 
deriving instance Show Term
deriving instance Eq Term

instance HasLoc Term where
  getLoc (Var loc _) = loc
  getLoc (Xtor loc _ _ _) = loc
  getLoc (Semi loc _ _ _) = loc
  getLoc (MuAbs loc _ _) = loc
  getLoc (Dtor loc _ _ _) = loc
  getLoc (Case loc _) = loc
  getLoc (CaseOf loc _ _) = loc
  getLoc (Cocase loc _) = loc
  getLoc (CocaseOf loc _ _) = loc
  getLoc (PrimLitI64 loc _) = loc
  getLoc (PrimLitF64 loc _) = loc
  getLoc (PrimLitChar loc _) = loc
  getLoc (PrimLitString loc _) = loc
  getLoc (NatLit loc _ _) = loc
  getLoc (TermParens loc _) = loc
  getLoc (FunApp loc _ _) = loc
  getLoc (Lambda loc _ _) = loc
  getLoc (CoLambda loc _ _) = loc
  getLoc (Apply loc _ _) = loc 
  getLoc (PrimTerm loc _ _) = loc 