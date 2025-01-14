module Pretty.Program where

import Data.List (intersperse)
import Data.Map qualified as M
import Prettyprinter

import Driver.Environment
import Pretty.Pretty
import Pretty.Terms ()
import Pretty.Types ()
import Pretty.Common
import Sugar.Desugar (Desugar(..))
import Syntax.CST.Program qualified as CST
import Syntax.CST.Types qualified as CST
import Syntax.CST.Types (PrdCns(..))
import Syntax.CST.Kinds
import Syntax.CST.Names
import Syntax.Core.Program qualified as Core
import Syntax.RST.Program qualified as RST
import Syntax.TST.Program qualified as TST
import Resolution.Unresolve
import Translate.EmbedTST (EmbedTST(..))
import Syntax.CST.Program (PrdCnsDeclaration(pcdecl_term))

---------------------------------------------------------------------------------
-- Data declarations
---------------------------------------------------------------------------------

instance PrettyAnn CST.DataDecl where
  prettyAnn (CST.MkDataDecl _ _ ref tn dc knd xtors) =
    (case ref of
      CST.Refined -> annKeyword "refinement" <+> mempty
      CST.NotRefined -> mempty) <>
    prettyAnn dc <+>
    prettyAnn tn <+>
    (case knd of
        Nothing -> mempty
        Just knd' ->
            colon <+>
            prettyAnn knd') <+>
    braces (mempty <+> cat (punctuate " , " (prettyAnn <$> xtors)) <+> mempty) <>
    semi

instance PrettyAnn RST.DataDecl where
  prettyAnn decl = prettyAnn (runUnresolveM (unresolve decl))

instance PrettyAnn TST.DataDecl where 
  prettyAnn decl = prettyAnn (embedTST decl)


---------------------------------------------------------------------------------
-- Producer / Consumer Declarations
---------------------------------------------------------------------------------

instance PrettyAnn CST.PrdCnsDeclaration where
  prettyAnn CST.MkPrdCnsDeclaration { pcdecl_pc, pcdecl_isRec = CST.Recursive, pcdecl_name, pcdecl_annot, pcdecl_term} =
    annKeyword "def" <+>
    annKeyword "rec" <+>
    prettyPrdCns pcdecl_pc <+>
    prettyAnn pcdecl_name <+>
    prettyAnnot pcdecl_annot <+>
    annSymbol ":=" <+>
    prettyAnn pcdecl_term <>
    semi
  prettyAnn CST.MkPrdCnsDeclaration { pcdecl_pc, pcdecl_isRec = CST.NonRecursive, pcdecl_name, pcdecl_annot, pcdecl_term} =
    annKeyword "def" <+>
    prettyPrdCns pcdecl_pc <+>
    prettyAnn pcdecl_name <+>
    prettyAnnot pcdecl_annot <+>
    annSymbol ":=" <+>
    prettyAnn pcdecl_term <>
    semi

prettyAnnot :: Maybe CST.TypeScheme -> Doc Annotation
prettyAnnot Nothing    = mempty
prettyAnnot (Just tys) = annSymbol ":" <+> prettyAnn tys

---------------------------------------------------------------------------------
-- Command Declarations
---------------------------------------------------------------------------------

instance PrettyAnn CST.CommandDeclaration where
  prettyAnn CST.MkCommandDeclaration { cmddecl_name, cmddecl_cmd } =
    annKeyword "def" <+>
    annKeyword "cmd" <+>
    prettyAnn cmddecl_name <+>
    annSymbol ":=" <+>
    prettyAnn cmddecl_cmd <>
    semi

---------------------------------------------------------------------------------
-- Structural Xtor Declaration
---------------------------------------------------------------------------------

-- | Prettyprint the list of MonoKinds
prettyCCList :: [(PrdCns, MonoKind)] -> Doc Annotation
prettyCCList xs =  parens' comma ((\(pc,k) -> case pc of Prd -> prettyAnn k; Cns -> annKeyword "return" <+> prettyAnn k) <$> xs)

instance PrettyAnn CST.StructuralXtorDeclaration where
  prettyAnn CST.MkStructuralXtorDeclaration { strxtordecl_xdata, strxtordecl_name, strxtordecl_arity, strxtordecl_evalOrder } =
    annKeyword (case strxtordecl_xdata of CST.Data -> "constructor"; CST.Codata -> "destructor") <+>
    prettyAnn strxtordecl_name <>
    prettyCCList strxtordecl_arity <+>
    (case strxtordecl_evalOrder of
        Nothing -> mempty
        Just strxtordecl_evalOrder' ->
            colon <+>
            prettyAnn strxtordecl_evalOrder') <>
    semi

---------------------------------------------------------------------------------
-- Import Declaration
---------------------------------------------------------------------------------

instance PrettyAnn CST.ImportDeclaration where
  prettyAnn CST.MkImportDeclaration { imprtdecl_module } =
    annKeyword "import" <+>
    prettyAnn imprtdecl_module <>
    semi

---------------------------------------------------------------------------------
-- Set Declaration
---------------------------------------------------------------------------------

instance PrettyAnn CST.SetDeclaration where
  prettyAnn CST.MkSetDeclaration { setdecl_option } =
    annKeyword "set" <+>
    prettyAnn setdecl_option <>
    semi

---------------------------------------------------------------------------------
-- Type Operator Declaration
---------------------------------------------------------------------------------

instance PrettyAnn CST.TyOpDeclaration where
  prettyAnn CST.MkTyOpDeclaration { tyopdecl_sym, tyopdecl_prec, tyopdecl_assoc, tyopdecl_res } =
    annKeyword "type" <+>
    annKeyword "operator" <+>
    prettyAnn tyopdecl_sym <+>
    prettyAnn tyopdecl_assoc <+>
    annKeyword "at" <+>
    prettyAnn tyopdecl_prec <+>
    annSymbol ":=" <+>
    prettyAnn tyopdecl_res <>
    semi

---------------------------------------------------------------------------------
-- Type Synonym Declaration
---------------------------------------------------------------------------------

instance PrettyAnn CST.TySynDeclaration where
  prettyAnn CST.MkTySynDeclaration { tysyndecl_name, tysyndecl_res } =
    annKeyword "type" <+>
    prettyAnn tysyndecl_name <+>
    annSymbol ":=" <+>
    prettyAnn tysyndecl_res <>
    semi

---------------------------------------------------------------------------------
-- Class Declaration
---------------------------------------------------------------------------------

-- | Prettyprint list of type variables for class declaration.
prettyTVars :: [(Variance, SkolemTVar, MonoKind)] -> Doc Annotation
prettyTVars tvs = parens $ cat (punctuate comma (prettyTParam <$> tvs))

instance PrettyAnn CST.ClassDeclaration where
  prettyAnn CST.MkClassDeclaration { classdecl_name, classdecl_kinds, classdecl_methods} =
    annKeyword "class" <+>
    prettyAnn classdecl_name <+>
    prettyTVars classdecl_kinds <+>
    braces (group (nest 3 (line' <> vsep (punctuate comma (prettyAnn <$> classdecl_methods))))) <>
    semi

---------------------------------------------------------------------------------
-- Instance Declaration
---------------------------------------------------------------------------------

instance PrettyAnn CST.InstanceDeclaration where
  prettyAnn CST.MkInstanceDeclaration { instancedecl_name, instancedecl_class, instancedecl_typ, instancedecl_cases } =
    annKeyword "instance" <+>
    prettyAnn instancedecl_name <+> annSymbol ":" <+>
    prettyAnn instancedecl_class <+>
    prettyAnn instancedecl_typ <+>
    braces (group (nest 3 (line' <> vsep (punctuate comma (prettyAnn <$> instancedecl_cases))))) <>
    semi

---------------------------------------------------------------------------------
-- Declaration
---------------------------------------------------------------------------------

instance PrettyAnn Core.Declaration where
  prettyAnn decl = prettyAnn (embedCore decl)

instance PrettyAnn TST.Declaration where
  prettyAnn decl = prettyAnn (embedTST decl)

instance PrettyAnn RST.Declaration where
  prettyAnn decl = prettyAnn (runUnresolveM (unresolve decl))

    
instance PrettyAnn CST.Declaration where
  prettyAnn (CST.PrdCnsDecl decl) = prettyAnn decl
  prettyAnn (CST.CmdDecl decl) = prettyAnn decl
  prettyAnn (CST.DataDecl decl) = prettyAnn decl
  prettyAnn (CST.XtorDecl decl) = prettyAnn decl
  prettyAnn (CST.ImportDecl decl) = prettyAnn decl
  prettyAnn (CST.SetDecl decl) = prettyAnn decl
  prettyAnn (CST.TyOpDecl decl) = prettyAnn decl
  prettyAnn (CST.TySynDecl decl) = prettyAnn decl
  prettyAnn (CST.ClassDecl decl) = prettyAnn decl
  prettyAnn (CST.InstanceDecl decl) = prettyAnn decl  
  prettyAnn CST.ParseErrorDecl = "<PARSE ERROR: SHOULD NOT OCCUR>"

---------------------------------------------------------------------------------
-- Program
---------------------------------------------------------------------------------

instance PrettyAnn CST.Module where
  prettyAnn CST.MkModule { mod_name, mod_decls } = vsep (moduleDecl : (prettyAnn <$> mod_decls))
    where moduleDecl = annKeyword "module" <+> prettyAnn mod_name <> semi

instance PrettyAnn TST.Module where
  prettyAnn TST.MkModule { mod_name, mod_decls } = vsep (moduleDecl : (prettyAnn <$> mod_decls))
    where moduleDecl = annKeyword "module" <+> prettyAnn mod_name <> semi

---------------------------------------------------------------------------------
-- Prettyprinting of Environments
---------------------------------------------------------------------------------

instance PrettyAnn Environment where
  prettyAnn MkEnvironment { prdEnv, cnsEnv, cmdEnv, declEnv } =
    vsep [ppPrds,ppCns,ppCmds, ppDecls ]
    where
      ppPrds = case M.toList prdEnv of
        [] -> mempty
        env -> vsep $ intersperse "" $ ("Producers:" : ( (\(v,(_,_,ty)) -> prettyAnn v <+> ":" <+> prettyAnn ty) <$> env)) ++ [""]
      ppCns  = case M.toList cnsEnv of
        [] -> mempty
        env -> vsep $ intersperse "" $ ("Consumers:" : ( (\(v,(_,_,ty)) -> prettyAnn v <+> ":" <+> prettyAnn ty) <$> env)) ++ [""]
      ppCmds = case M.toList cmdEnv of
        [] -> mempty
        env -> vsep $ intersperse "" $ ("Commands" : ( (\(v,_) -> prettyAnn v) <$> env)) ++ [""]
      ppDecls = case declEnv of
        [] -> mempty
        env -> vsep $ intersperse "" $ ("Type declarations:" : (prettyAnn . snd <$> env)) ++ [""]

