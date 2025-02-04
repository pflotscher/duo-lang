module Syntax.CST.Program where

import Data.Text (Text)

import Syntax.CST.Terms ( Term, TermCase )
import Syntax.CST.Types
    ( TypeScheme, XtorSig, Typ, DataCodata, PrdCns )
import Syntax.CST.Names
    ( Associativity,
      ClassName,
      DocComment,
      FreeVarName,
      ModuleName (..),
      Precedence,
      SkolemTVar,
      TyOpName,
      TypeName,
      XtorName )
import Syntax.CST.Kinds
    ( EvaluationOrder, MonoKind, PolyKind, Variance )
import Loc ( HasLoc(..), Loc, defaultLoc )
import Errors (Error, throwOtherError)
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T
import Data.List
import System.FilePath (joinPath, splitDirectories, dropExtension)
import Pretty.Pretty (ppPrintString)
import Pretty.Common ()

---------------------------------------------------------------------------------
-- Producer / Consumer Declaration
---------------------------------------------------------------------------------

data IsRec where
  Recursive :: IsRec
  NonRecursive :: IsRec
  deriving (Show, Eq, Ord)

-- | A toplevel producer or consumer declaration.
data PrdCnsDeclaration = MkPrdCnsDeclaration
  { pcdecl_loc :: Loc
    -- ^ The source code location of the declaration.
  , pcdecl_doc :: Maybe DocComment
    -- ^ The documentation string of the declaration.
  , pcdecl_pc :: PrdCns
    -- ^ Whether a producer or consumer is declared.
  , pcdecl_isRec :: IsRec
    -- ^ Whether the declaration can refer to itself recursively.
  , pcdecl_name :: FreeVarName
    -- ^ The name of the producer / consumer.
  , pcdecl_annot :: Maybe TypeScheme
    -- ^ The type signature.
  , pcdecl_term :: Term
    -- ^ The term itself.
}

deriving instance Show PrdCnsDeclaration

instance HasLoc PrdCnsDeclaration where
  getLoc = pcdecl_loc

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
  , cmddecl_cmd :: Term
    -- ^ The command itself.
  }

deriving instance Show CommandDeclaration

instance HasLoc CommandDeclaration where
  getLoc = cmddecl_loc

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
  , strxtordecl_evalOrder :: Maybe EvaluationOrder
    -- Optional evaluation order of the structural type to which the
    -- constructor/destructor belongs.
    -- If no evaluation order is indicated, then it will default to CBV for constructors
    -- and CBN for destructors.
  }

deriving instance Show StructuralXtorDeclaration

instance HasLoc StructuralXtorDeclaration where
  getLoc = strxtordecl_loc

---------------------------------------------------------------------------------
-- Import Declaration
---------------------------------------------------------------------------------

-- | A toplevel import statment.
data ImportDeclaration = MkImportDeclaration
  { imprtdecl_loc :: Loc
    -- ^ The source code location of the import.
  , imprtdecl_doc :: Maybe DocComment
    -- ^ The documentation string of the import.
  , imprtdecl_module :: ModuleName
    -- ^ The imported module.
  }

deriving instance Show ImportDeclaration

instance HasLoc ImportDeclaration where
  getLoc = imprtdecl_loc

---------------------------------------------------------------------------------
-- Set Declaration
---------------------------------------------------------------------------------

-- | A toplevel configuration option.
data SetDeclaration = MkSetDeclaration
  { setdecl_loc :: Loc
    -- ^ The source code location of the option.
  , setdecl_doc :: Maybe DocComment
    -- ^ The documentation string of the option.
  , setdecl_option :: Text
    -- ^ The option itself.
  }

deriving instance Show SetDeclaration

instance HasLoc SetDeclaration where
  getLoc = setdecl_loc

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
  , tyopdecl_res :: TypeName
    -- ^ The typename that the operator should stand for.
  }

deriving instance Show TyOpDeclaration

instance HasLoc TyOpDeclaration where
  getLoc = tyopdecl_loc

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
  , tysyndecl_res :: Typ
    -- ^ What the type synonym should be replaced with.
  }

deriving instance Show TySynDeclaration

instance HasLoc TySynDeclaration where
  getLoc = tysyndecl_loc

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
  , instancedecl_typ :: Typ
    -- ^ The type the instance is being defined for.
  , instancedecl_cases :: [TermCase]
    -- ^ The method definitions for the class.
  }

deriving instance Show InstanceDeclaration

instance HasLoc InstanceDeclaration where
  getLoc = instancedecl_loc

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
  , classdecl_methods :: [XtorSig]
    -- ^ The type class methods and their types.
  }

deriving instance Show ClassDeclaration

instance HasLoc ClassDeclaration where
  getLoc = classdecl_loc

------------------------------------------------------------------------------
-- Data Type declarations
------------------------------------------------------------------------------

data IsRefined = Refined | NotRefined
  deriving (Show, Ord, Eq)

-- | A toplevel declaration of a data or codata type.
data DataDecl = MkDataDecl
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

deriving instance Show DataDecl

instance HasLoc DataDecl where
  getLoc = data_loc

---------------------------------------------------------------------------------
-- Declarations
---------------------------------------------------------------------------------

data Declaration where
  PrdCnsDecl     :: PrdCnsDeclaration         -> Declaration
  CmdDecl        :: CommandDeclaration        -> Declaration
  DataDecl       :: DataDecl                  -> Declaration
  XtorDecl       :: StructuralXtorDeclaration -> Declaration
  ImportDecl     :: ImportDeclaration         -> Declaration
  SetDecl        :: SetDeclaration            -> Declaration
  TyOpDecl       :: TyOpDeclaration           -> Declaration
  TySynDecl      :: TySynDeclaration          -> Declaration
  ClassDecl      :: ClassDeclaration          -> Declaration
  InstanceDecl   :: InstanceDeclaration       -> Declaration
  ParseErrorDecl ::                              Declaration

instance Show Declaration where
  show _ = "<Show for Declaration not implemented>"

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

-- when only given a filepath, parsing the file will result in the libpath of a module overlapping with the module name, e.g.
-- module Codata.Function in std/Codata/Function.duo will have libpath `std/Codata`.
-- Thus we have to adjust the libpath (to `std/` in the example above).
-- Moreover, we need to check whether the new path and the original filepath are compatible.
adjustModulePath :: Module -> FilePath -> Either (NE.NonEmpty Error) Module
adjustModulePath mod fp =
  let fp'  = fpToList fp
      mlp  = mod_libpath mod
      mFp  = fpToList mlp
      mn   = mod_name mod
      mp   = T.unpack <$> mn_path mn ++ [mn_base mn]
  in do
    prefix <- reverse <$> dropModulePart (reverse mp) (reverse mFp)
    if prefix `isPrefixOf` fp'
    then pure mod { mod_libpath = joinPath prefix } 
    else throwOtherError defaultLoc [ "Module name " <> T.pack (ppPrintString mlp) <> " is not compatible with given filepath " <> T.pack fp ]
  where
    fpToList :: FilePath -> [String]
    fpToList = splitDirectories . dropExtension

    dropModulePart :: [String] -> [String] -> Either (NE.NonEmpty Error) [String]
    dropModulePart mp mFp =
      case stripPrefix mp mFp of
        Just mFp' -> pure mFp'
        Nothing   -> throwOtherError defaultLoc [ "Module name " <> T.pack (ppPrintString (mod_name mod)) <> " is not a suffix of path " <> T.pack (mod_libpath mod)  ]
