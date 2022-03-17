module Syntax.CST.Terms where

import Data.List.NonEmpty (NonEmpty(..))
import Text.Megaparsec.Pos (SourcePos)

import Syntax.Common
import Utils
import Syntax.Primitives

--------------------------------------------------------------------------------------------
-- Substitutions and Binding Sites
--------------------------------------------------------------------------------------------

data PrdCnsTerm where
    PrdTerm :: Term -> PrdCnsTerm
    CnsTerm :: Term -> PrdCnsTerm

deriving instance Show PrdCnsTerm
deriving instance Eq PrdCnsTerm

type Substitution = [PrdCnsTerm]
type SubstitutionI = (Substitution,PrdCns,Substitution)

substitutionToArity :: Substitution -> Arity
substitutionToArity = map f
  where
    f (PrdTerm _) = Prd
    f (CnsTerm _) = Cns

substitutionIToArity :: SubstitutionI -> Arity
substitutionIToArity (subst1, pc, subst2) =
  substitutionToArity subst1 ++ [case pc of Prd -> Cns; Cns -> Prd] ++ substitutionToArity subst2

type BindingSite = [(PrdCns,FreeVarName)]
type BindingSiteI = (BindingSite, (), BindingSite)

--------------------------------------------------------------------------------------------
-- Cases/Cocases
--------------------------------------------------------------------------------------------

type CommandCase = (Loc, XtorName, BindingSite,  Command)
type TermCase    = (Loc, XtorName, BindingSite,  Term)
type TermCaseI   = (Loc, XtorName, BindingSiteI, Term)

--------------------------------------------------------------------------------------------
-- Terms
--------------------------------------------------------------------------------------------

data Term where
    -- AST Nodes
    Var :: Loc -> FreeVarName -> Term
    Xtor :: Loc -> XtorName -> Substitution -> Term
    XMatch :: Loc -> DataCodata -> [CommandCase] -> Term
    MuAbs :: Loc -> FreeVarName -> Command -> Term
    Dtor :: Loc -> XtorName -> Term -> SubstitutionI -> Term
    Case :: Loc -> Term -> [TermCase] -> Term
    Cocase :: Loc -> [TermCaseI] -> Term
    PrimLit :: Loc -> PrimitiveLiteral -> Term
    -- Sugar Nodes
    DtorChain :: SourcePos -> Term -> NonEmpty (XtorName, SubstitutionI, SourcePos) -> Term
    NatLit :: Loc -> NominalStructural -> Int -> Term
    TermParens :: Loc -> Term -> Term
    FunApp :: Loc -> Term -> Term -> Term
    MultiLambda :: Loc -> [FreeVarName] -> Term -> Term
    Lambda :: Loc -> FreeVarName -> Term -> Term

deriving instance Show Term
deriving instance Eq Term

getLoc :: Term -> Loc
getLoc (Var loc _) = loc
getLoc (Xtor loc _ _) = loc
getLoc (XMatch loc _ _) = loc
getLoc (MuAbs loc _ _) = loc
getLoc (Dtor loc _ _ _) = loc
getLoc (Case loc _ _) = loc
getLoc (Cocase loc _) = loc
getLoc (PrimLit loc _) = loc
getLoc (DtorChain _ tm _)  = getLoc tm
getLoc (NatLit loc _ _) = loc
getLoc (TermParens loc _) = loc
getLoc (FunApp loc _ _) = loc
getLoc (MultiLambda loc _ _) = loc
getLoc (Lambda loc _ _) = loc

--------------------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------------------

data Command where
  -- AST Nodes
  Apply :: Loc -> Term -> Term -> Command
  Print :: Loc -> Term -> Command -> Command
  Read  :: Loc -> Term -> Command
  Call  :: Loc -> FreeVarName -> Command
  Done  :: Loc -> Command
  -- Sugar Nodes
  CommandParens :: Loc -> Command -> Command

deriving instance Show Command
deriving instance Eq Command
