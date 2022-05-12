module Syntax.Common.TypesUnpol where

import Syntax.Common
import Data.List.NonEmpty (NonEmpty)
import Utils ( Loc )

---------------------------------------------------------------------------------
-- Parse Types
---------------------------------------------------------------------------------

data Typ where
  TyVar :: Loc -> TVar -> Typ
  TyXData :: Loc -> DataCodata -> Maybe TypeName -> [XtorSig] -> Typ
  TyNominal :: Loc -> TypeName -> [Typ] -> Typ
  TyRec :: Loc -> TVar -> Typ -> Typ
  TyTop :: Loc -> Typ
  TyBot :: Loc -> Typ
  TyPrim :: Loc -> PrimitiveType -> Typ
  -- | A chain of binary type operators generated by the parser
  -- Lowering will replace "TyBinOpChain" nodes with "TyBinOp" nodes.
  TyBinOpChain :: Typ -> NonEmpty (Loc, BinOp,  Typ) -> Typ
  -- | A binary type operator waiting to be desugared
  -- This is used as an intermediate representation by lowering and
  -- should never be directly constructed elsewhere.
  TyBinOp :: Loc -> Typ -> BinOp -> Typ -> Typ
  TyParens :: Loc -> Typ -> Typ
  deriving Show

data XtorSig = MkXtorSig
  { sig_name :: XtorName
  , sig_args :: LinearContext
  }
  deriving Show

data PrdCnsTyp where
  PrdType :: Typ -> PrdCnsTyp
  CnsType :: Typ -> PrdCnsTyp
  deriving Show

type LinearContext = [PrdCnsTyp]

linearContextToArity :: LinearContext -> Arity
linearContextToArity = map f
  where
    f (PrdType _) = Prd
    f (CnsType _) = Cns

data TypeScheme = TypeScheme
  { ts_loc :: Loc
  , ts_vars :: [TVar]
  , ts_monotype :: Typ
  }
  deriving Show

------------------------------------------------------------------------------
-- Data Type declarations
------------------------------------------------------------------------------

data DataDecl = NominalDecl
  { data_refined :: IsRefined
  , data_name :: TypeName
  , data_polarity :: DataCodata
  , data_kind :: Maybe PolyKind
  , data_xtors :: [XtorSig]
  }