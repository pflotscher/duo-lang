{-# LANGUAGE UndecidableInstances #-}
module Syntax.RST.Program where

import Syntax.RST.Terms( Command, Term, InstanceCase )
import Syntax.RST.Types ( TypeScheme, Typ, MethodSig, XtorSig, Polarity(..), PolarityRep(..))
import Syntax.CST.Names
    ( Associativity,
      ClassName,
      DocComment,
      FreeVarName,
      Precedence,
      RnTypeName,
      SkolemTVar,
      TyOpName,
      TypeName,
      ModuleName,
      XtorName )
import Syntax.CST.Kinds
    ( EvaluationOrder, MonoKind, PolyKind, Variance )
import Syntax.CST.Types ( DataCodata, PrdCns(..), PrdCnsRep(..) )

import Loc ( Loc )
import Syntax.CST.Program qualified as CST

---------------------------------------------------------------------------------
-- Producer / Consumer Tags
---------------------------------------------------------------------------------

-- | We map producer terms to positive types, and consumer terms to negative types.
type family PrdCnsToPol (pc :: PrdCns) :: Polarity where
  PrdCnsToPol Prd = Pos
  PrdCnsToPol Cns = Neg

prdCnsToPol :: PrdCnsRep pc -> PolarityRep (PrdCnsToPol pc)
prdCnsToPol PrdRep = PosRep
prdCnsToPol CnsRep = NegRep

---------------------------------------------------------------------------------
-- Producer / Consumer Declaration
---------------------------------------------------------------------------------

-- | A toplevel producer or consumer declaration.
data PrdCnsDeclaration pc = MkPrdCnsDeclaration
  { pcdecl_loc :: Loc
    -- ^ The source code location of the declaration.
  , pcdecl_doc :: Maybe DocComment
    -- ^ The documentation string of the declaration.
  , pcdecl_pc :: PrdCnsRep pc
    -- ^ Whether a producer or consumer is declared.
  , pcdecl_isRec :: CST.IsRec
    -- ^ Whether the declaration can refer to itself recursively.
  , pcdecl_name :: FreeVarName
    -- ^ The name of the producer / consumer.
  , pcdecl_annot :: Maybe (TypeScheme (PrdCnsToPol pc))
    -- ^ The type signature.
  , pcdecl_term :: Term pc
    -- ^ The term itself.
}

deriving instance (Show (PrdCnsDeclaration Prd))
deriving instance (Show (PrdCnsDeclaration Cns))

---------------------------------------------------------------------------------
-- Command Declaration
---------------------------------------------------------------------------------

-- | A toplevel command declaration.
data CommandDeclaration = MkCommandDeclaration
  { cmddecl_loc :: Loc
    -- ^ The source code location of the declaration.
  , cmddecl_doc :: Maybe DocComment
    -- ^ The documentation string of the declaration.
  , cmddecl_name :: FreeVarName
    -- ^ The name of the command.
  , cmddecl_cmd :: Command
    -- ^ The command itself.
  }

deriving instance (Show CommandDeclaration)

---------------------------------------------------------------------------------
-- Structural Xtor Declaration
---------------------------------------------------------------------------------

-- | A toplevel declaration of a constructor or destructor.
-- These declarations are needed for structural data and codata types.
data StructuralXtorDeclaration = MkStructuralXtorDeclaration
  { 
    strxtordecl_loc :: Loc
    -- ^ The source code location of the declaration.
  , strxtordecl_doc :: Maybe DocComment
    -- ^ The documenation string of the declaration.
  , strxtordecl_xdata :: DataCodata
    -- ^ Indicates whether a constructor (Data) or destructor (Codata) is declared.
  , strxtordecl_name :: XtorName
    -- ^ The name of the declared constructor or destructor.
  , strxtordecl_arity :: [(PrdCns, MonoKind)]
    -- ^ The arguments of the constructor/destructor.
    -- Each argument can either be a constructor or destructor.
    -- The MonoKind (CBV or CBN) of each argument has to be specified.
  , strxtordecl_evalOrder :: EvaluationOrder
    -- Evaluation order of the structural type to which the
    -- constructor/destructor belongs.
  }

deriving instance (Show StructuralXtorDeclaration)

---------------------------------------------------------------------------------
-- Type Operator Declaration
---------------------------------------------------------------------------------

-- | A toplevel declaration of a type operator.
data TyOpDeclaration = MkTyOpDeclaration
  { tyopdecl_loc :: Loc
    -- ^ The source code location of the declaration.
  , tyopdecl_doc :: Maybe DocComment
    -- ^ The documentation string of the declaration.
  , tyopdecl_sym :: TyOpName
    -- ^ The symbol used for the type operator.
  , tyopdecl_prec :: Precedence
    -- ^ The precedence level of the type operator.
  , tyopdecl_assoc :: Associativity
    -- ^ The associativity of the type operator.
  , tyopdecl_res :: RnTypeName
    -- ^ The typename that the operator should stand for.
  }

deriving instance Show TyOpDeclaration

---------------------------------------------------------------------------------
-- Type Synonym Declaration
---------------------------------------------------------------------------------

-- | A toplevel declaration of a type synonym.
data TySynDeclaration = MkTySynDeclaration
  { tysyndecl_loc :: Loc
    -- ^ The source code location of the declaration.
  , tysyndecl_doc :: Maybe DocComment
    -- ^ The documentation string of the declaration.
  , tysyndecl_name :: TypeName
    -- ^ The name of the type synonym that is being introduced.
  , tysyndecl_res :: (Typ Pos, Typ Neg)
    -- ^ What the type synonym should be replaced with.
  }

deriving instance Show TySynDeclaration

------------------------------------------------------------------------------
-- Instance Declaration
------------------------------------------------------------------------------

data InstanceDeclaration = MkInstanceDeclaration
  { instancedecl_loc :: Loc
    -- ^ The source code location of the declaration.
  , instancedecl_doc :: Maybe DocComment
    -- ^ The documentation string of the declaration.
  , instancedecl_name :: FreeVarName
    -- ^ The name of the instance declaration.
  , instancedecl_class :: ClassName
    -- ^ The name of the type class the instance is for.
  , instancedecl_typ :: (Typ Pos, Typ Neg)
    -- ^ The type the instance is being defined for.
  , instancedecl_cases :: [InstanceCase]
    -- ^ The method definitions for the class.
  }

deriving instance Show InstanceDeclaration

------------------------------------------------------------------------------
-- Class Declaration
------------------------------------------------------------------------------

data ClassDeclaration = MkClassDeclaration
  { classdecl_loc :: Loc
    -- ^ The source code location of the declaration.
  , classdecl_doc :: Maybe DocComment
    -- ^ The documentation string of the declaration.
  , classdecl_name :: ClassName
    -- ^ The name of the type class that is being introduced.
  , classdecl_kinds :: [(Variance, SkolemTVar, MonoKind)]
    -- ^ The kind of the type class variables.
  , classdecl_methods :: ([MethodSig Pos], [MethodSig Neg])
    -- ^ The type class methods and their types.
  }

deriving instance Show ClassDeclaration

------------------------------------------------------------------------------
-- Data Type declarations
------------------------------------------------------------------------------

-- | A toplevel declaration of a data or codata type.
data DataDecl =
    NominalDecl
  { data_loc :: Loc
    -- ^ The source code location of the declaration.
  , data_doc :: Maybe DocComment
    -- ^ The documentation string of the declaration.
  , data_name :: RnTypeName
    -- ^ The name of the type. E.g. "List".
  , data_polarity :: DataCodata
    -- ^ Whether a data or codata type is declared.
  , data_kind :: PolyKind
    -- ^ The kind of the type constructor.
  , data_xtors :: ([XtorSig Pos], [XtorSig Neg])
    -- The constructors/destructors of the declaration.
  }
  | RefinementDecl
  { data_loc :: Loc
    -- ^ The source code location of the declaration.
  , data_doc :: Maybe DocComment
    -- ^ The documentation string of the declaration.
  , data_name :: RnTypeName
    -- ^ The name of the type. E.g. "List".
  , data_polarity :: DataCodata
    -- ^ Whether a data or codata type is declared.
  , data_kind :: PolyKind
    -- ^ The kind of the type constructor.
  , data_xtors :: ([XtorSig Pos], [XtorSig Neg])
    -- ^ The constructors/destructors of the declaration,
    -- as written by the user.
  }

deriving instance Show DataDecl

---------------------------------------------------------------------------------
-- Declarations
---------------------------------------------------------------------------------

data Declaration where
  PrdCnsDecl   :: PrdCnsRep pc -> PrdCnsDeclaration pc -> Declaration
  CmdDecl      :: CommandDeclaration                   -> Declaration
  DataDecl     :: DataDecl                             -> Declaration
  XtorDecl     :: StructuralXtorDeclaration            -> Declaration
  ImportDecl   :: CST.ImportDeclaration                -> Declaration
  SetDecl      :: CST.SetDeclaration                   -> Declaration
  TyOpDecl     :: TyOpDeclaration                      -> Declaration
  TySynDecl    :: TySynDeclaration                     -> Declaration
  ClassDecl    :: ClassDeclaration                     -> Declaration
  InstanceDecl :: InstanceDeclaration                  -> Declaration
  

instance Show Declaration where
  show (PrdCnsDecl PrdRep decl) = show decl
  show (PrdCnsDecl CnsRep decl) = show decl
  show (CmdDecl           decl) = show decl
  show (DataDecl          decl) = show decl
  show (XtorDecl          decl) = show decl
  show (ImportDecl        decl) = show decl
  show (SetDecl           decl) = show decl
  show (TyOpDecl          decl) = show decl
  show (TySynDecl         decl) = show decl
  show (ClassDecl         decl) = show decl
  show (InstanceDecl      decl) = show decl

---------------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------------

-- | A module which corresponds to a single '*.duo' file.
data Module = MkModule
  { mod_name :: ModuleName
    -- ^ The name of the module.
  , mod_libpath :: FilePath
    -- ^ The absolute filepath of the library of the module.
  , mod_decls :: [Declaration]
    -- ^ The declarations contained in the module.
  }

deriving instance Show Module
