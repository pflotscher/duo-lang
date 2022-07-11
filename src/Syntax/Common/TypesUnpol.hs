module Syntax.Common.TypesUnpol where

import Syntax.Common
import Data.List.NonEmpty (NonEmpty)
import Utils ( Loc, HasLoc(..))

---------------------------------------------------------------------------------
-- Parse Types
---------------------------------------------------------------------------------

data Typ where
  TyUniVar :: Loc -> UniTVar -> Typ
  TySkolemVar :: Loc -> SkolemTVar -> Typ
  TyXData    :: Loc -> DataCodata             -> [XtorSig] -> Typ
  TyXRefined :: Loc -> DataCodata -> TypeName -> [XtorSig] -> Typ
  TyNominal :: Loc -> TypeName -> [Typ] -> Typ
  TyRec :: Loc -> SkolemTVar -> Typ -> Typ
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

instance HasLoc Typ where
  getLoc (TyUniVar loc _) = loc
  getLoc (TySkolemVar loc _) = loc
  getLoc (TyXData loc _ _) = loc
  getLoc (TyXRefined loc _ _ _) = loc
  getLoc (TyNominal loc _ _) = loc
  getLoc (TyRec loc _ _) = loc
  getLoc (TyTop loc) = loc
  getLoc (TyBot loc) = loc
  getLoc (TyPrim loc _) = loc
  -- Implementation of getLoc for TyBinOpChain a bit hacky!
  getLoc (TyBinOpChain ty _) = getLoc ty
  getLoc (TyBinOp loc _ _ _) = loc
  getLoc (TyParens loc _) = loc

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
  , ts_vars :: [SkolemTVar]
  , ts_constraints :: [Constraint]
  , ts_monotype :: Typ
  }
  deriving Show

instance HasLoc TypeScheme where
  getLoc ts = ts_loc ts

------------------------------------------------------------------------------
-- Data Type declarations
------------------------------------------------------------------------------

-- | A toplevel declaration of a data or codata type.
data DataDecl = NominalDecl
  { data_loc :: Loc
    -- ^ The source code location of the declaration.
  , data_doc :: Maybe DocComment
    -- ^ The documentation string of the declaration.
  , data_refined :: IsRefined
    -- ^ Whether an ordinary or a refinement type is declared.
  , data_name :: TypeName
    -- ^ The name of the type. E.g. "List".
  , data_polarity :: DataCodata
    -- ^ Whether a data or codata type is declared.
  , data_kind :: Maybe PolyKind
    -- ^ The kind of the type constructor.
  , data_xtors :: [XtorSig]
    -- The constructors/destructors of the declaration.
  }

deriving instance (Show DataDecl)

instance HasLoc DataDecl where
  getLoc decl = data_loc decl

---------------------------------------------------------------------------------
-- Constraints
---------------------------------------------------------------------------------

data Constraint
  = SubType Typ Typ
  | TypeClass ClassName SkolemTVar
 deriving Show

