{-# LANGUAGE OverloadedStrings #-}
module Pretty.Pretty where

import qualified Data.Text as T
import qualified Data.Map as M
import Prettyprinter
import Prettyprinter.Render.String (renderString)
import System.Console.ANSI
import Text.Megaparsec.Pos

import Syntax.STerms
import Syntax.ATerms
import Syntax.Types
import Syntax.Program
import Utils

---------------------------------------------------------------------------------
-- Annotations
---------------------------------------------------------------------------------

data Annotation
  = AnnKeyword
  | AnnSymbol
  | AnnTypeName
  | AnnXtorName
  deriving (Show, Eq)

annKeyword :: Doc Annotation -> Doc Annotation
annKeyword = annotate AnnKeyword

annSymbol :: Doc Annotation -> Doc Annotation
annSymbol = annotate AnnSymbol

annTypeName :: Doc Annotation -> Doc Annotation
annTypeName = annotate AnnTypeName

annXtorName :: Doc Annotation -> Doc Annotation
annXtorName = annotate AnnXtorName

-- A variant of the `Pretty` typeclass which uses our annotations.
-- Why the builtin  Pretty class is not sufficient, see: https://github.com/quchen/prettyprinter/issues/102
class PrettyAnn a where
  prettyAnn :: a -> Doc Annotation

instance {-# OVERLAPPING #-} PrettyAnn String where
  prettyAnn = pretty

instance PrettyAnn a => PrettyAnn [a] where
  prettyAnn xs = list (prettyAnn <$> xs)

instance PrettyAnn Bool where
  prettyAnn = pretty

instance PrettyAnn () where
  prettyAnn = pretty

---------------------------------------------------------------------------------
-- Render to String Backend
---------------------------------------------------------------------------------

ppPrint :: PrettyAnn a => a -> String
ppPrint doc =
  let
    layout = defaultLayoutOptions { layoutPageWidth = AvailablePerLine 100 1 }
  in
    renderString (layoutPretty layout (prettyAnn doc))

---------------------------------------------------------------------------------
-- Console Backend with ANSI Colors
---------------------------------------------------------------------------------

annotationToOpts :: Annotation -> [SGR]
annotationToOpts AnnKeyword  = [SetColor Foreground Vivid Blue]
annotationToOpts AnnSymbol   = [SetColor Foreground Dull Red]
annotationToOpts AnnTypeName = [SetColor Foreground Dull Green]
annotationToOpts AnnXtorName = [SetColor Foreground Dull Magenta]

ppPrintIO :: PrettyAnn a => a -> IO ()
ppPrintIO doc =
  let
    layout = defaultLayoutOptions { layoutPageWidth = AvailablePerLine 100 1 }
  in
    renderConsole (layoutPretty layout (prettyAnn doc))

renderConsole :: SimpleDocStream Annotation -> IO ()
renderConsole str = (renderConsole' str) >> putStrLn ""

renderConsole' :: SimpleDocStream Annotation -> IO ()
renderConsole' = \case
  SFail        -> return ()
  SEmpty       -> return ()
  SChar c x    -> do
    putStr $ c : []
    renderConsole' x
  SText _l t x -> do
    putStr (T.unpack t)
    renderConsole' x
  SLine i x    -> do
    putStr ('\n' : T.unpack (T.replicate i (T.singleton ' ')))
    renderConsole' x
  SAnnPush ann x -> do
    setSGR (annotationToOpts ann)
    renderConsole' x
  SAnnPop x    -> do
    setSGR [Reset]
    renderConsole' x

---------------------------------------------------------------------------------
-- Helper functions
---------------------------------------------------------------------------------

intercalateX :: Doc ann -> [Doc ann] -> Doc ann
intercalateX  x xs = cat (punctuate x xs)

intercalateComma :: [Doc ann] -> Doc ann
intercalateComma xs = cat (punctuate comma xs)

prettyTwice' :: (PrettyAnn a, PrettyAnn b) => [a] -> [b] -> Doc Annotation
prettyTwice' xs ys = xs' <> ys'
  where
    xs' = if null xs then mempty else parens   (intercalateComma (map prettyAnn xs))
    ys' = if null ys then mempty else brackets (intercalateComma (map prettyAnn ys))

prettyTwice :: PrettyAnn a => Twice [a] -> Doc Annotation
prettyTwice (Twice xs ys) = prettyTwice' xs ys

instance PrettyAnn XtorName where
  prettyAnn (MkXtorName Structural xt) = annXtorName $ "'" <> prettyAnn xt
  prettyAnn (MkXtorName Nominal    xt) = annXtorName $ prettyAnn xt

-- | This identity wrapper is used to indicate that we want to transform the element to
-- a named representation before prettyprinting it.
newtype NamedRep a = NamedRep a

---------------------------------------------------------------------------------
-- Symmetric Terms
---------------------------------------------------------------------------------

instance PrettyAnn a => PrettyAnn (SCase a) where
  prettyAnn MkSCase{..} =
    prettyAnn scase_name <>
    prettyTwice scase_args <+>
    annSymbol "=>" <+>
    prettyAnn scase_cmd

instance PrettyAnn a => PrettyAnn (XtorArgs a) where
  prettyAnn (MkXtorArgs prds cns) = prettyTwice' prds cns

isNumSTerm :: STerm pc a -> Maybe Int
isNumSTerm (XtorCall PrdRep (MkXtorName Nominal "Z") (MkXtorArgs [] [])) = Just 0
isNumSTerm (XtorCall PrdRep (MkXtorName Nominal "S") (MkXtorArgs [n] [])) = case isNumSTerm n of
  Nothing -> Nothing
  Just n -> Just (n + 1)
isNumSTerm _ = Nothing

instance PrettyAnn a => PrettyAnn (STerm pc a) where
  prettyAnn (isNumSTerm -> Just n) = pretty n
  prettyAnn (BoundVar _ (i,j)) = parens (pretty i <> "," <> pretty j)
  prettyAnn (FreeVar _ v) = pretty v
  prettyAnn (XtorCall _ xt args) = prettyAnn xt <> prettyAnn args
  prettyAnn (XMatch PrdRep _ cases) =
    annKeyword "comatch" <+>
    braces (group (nest 3 (line' <> vsep (punctuate comma (prettyAnn <$> cases)))))
  prettyAnn (XMatch CnsRep _ cases) =
    annKeyword "match"   <+>
    braces (group (nest 3 (line' <> vsep (punctuate comma (prettyAnn <$> cases)))))
  prettyAnn (MuAbs pc a cmd) =
    annKeyword (case pc of {PrdRep -> "mu"; CnsRep -> "mu*"}) <+>
    prettyAnn a <> "." <> parens (prettyAnn cmd)

instance PrettyAnn a => PrettyAnn (Command a) where
  prettyAnn Done = annKeyword "Done"
  prettyAnn (Print t) = annKeyword "Print" <> parens (prettyAnn t)
  prettyAnn (Apply t1 t2) = group (nest 3 (line' <> vsep [prettyAnn t1, annSymbol ">>", prettyAnn t2]))

instance PrettyAnn (NamedRep (STerm pc FreeVarName)) where
  prettyAnn (NamedRep tm) = prettyAnn (openSTermComplete tm)

instance PrettyAnn (NamedRep (Command FreeVarName)) where
  prettyAnn (NamedRep cmd) = prettyAnn (openCommandComplete cmd)

---------------------------------------------------------------------------------
-- Asymmetric Terms
---------------------------------------------------------------------------------

isNumATerm :: ATerm a -> Maybe Int
isNumATerm (Ctor (MkXtorName Nominal "Z") []) = Just 0
isNumATerm (Ctor (MkXtorName Nominal "S") [n]) = case isNumATerm n of
  Nothing -> Nothing
  Just n -> Just (n + 1)
isNumATerm _ = Nothing

instance PrettyAnn a => PrettyAnn (ACase a) where
  prettyAnn MkACase{ acase_name, acase_args, acase_term } =
    prettyAnn acase_name <>
    parens (intercalateComma (prettyAnn <$> acase_args)) <+>
    annSymbol "=>" <+>
    prettyAnn acase_term

instance PrettyAnn a => PrettyAnn (ATerm a) where
  prettyAnn (isNumATerm -> Just n) = pretty n
  prettyAnn (BVar (i,j)) = parens (pretty i <> "," <> pretty j)
  prettyAnn (FVar v) = pretty v
  prettyAnn (Ctor xt args) = prettyAnn xt <> parens (intercalateComma (map prettyAnn args))
  prettyAnn (Dtor xt t args) =
    parens ( prettyAnn t <> "." <> prettyAnn xt <> parens (intercalateComma (map prettyAnn args)))
  prettyAnn (Match t cases) =
    annKeyword "match" <+>
    prettyAnn t <+>
    annKeyword "with" <+>
    braces (group (nest 3 (line' <> vsep (punctuate comma (prettyAnn <$> cases)))))
  prettyAnn (Comatch cocases) =
    annKeyword "comatch" <+>
    braces (group (nest 3 (line' <> vsep (punctuate comma (prettyAnn <$> cocases)))))

instance PrettyAnn (NamedRep (ATerm FreeVarName)) where
  prettyAnn (NamedRep tm) = prettyAnn (openATermComplete tm)

---------------------------------------------------------------------------------
-- Prettyprinting of Types
---------------------------------------------------------------------------------

instance PrettyAnn TVar where
  prettyAnn (MkTVar tv) = pretty tv

instance PrettyAnn (Typ pol) where
  prettyAnn (TySet PosRep []) = annKeyword "Bot"
  prettyAnn (TySet PosRep [t]) = prettyAnn t
  prettyAnn (TySet PosRep tts) = parens (intercalateX " \\/ " (map prettyAnn tts))
  prettyAnn (TySet NegRep []) = annKeyword "Top"
  prettyAnn (TySet NegRep [t]) = prettyAnn t
  prettyAnn (TySet NegRep tts) = parens (intercalateX " /\\ " (map prettyAnn tts))
  prettyAnn (TyVar _ tv) = prettyAnn tv
  prettyAnn (TyRec _ rv t) = annKeyword "rec " <> prettyAnn rv <> "." <> prettyAnn t
  prettyAnn (TyNominal _ tn) = prettyAnn tn
  prettyAnn (TyData _ xtors) =
    angles (mempty <+> cat (punctuate " | " (prettyAnn <$> xtors)) <+> mempty)
  prettyAnn (TyCodata _ xtors) =
    braces (mempty <+> cat (punctuate " , " (prettyAnn <$> xtors)) <+> mempty)

instance PrettyAnn (TypArgs a) where
  prettyAnn (MkTypArgs prdArgs cnsArgs) = prettyTwice' prdArgs cnsArgs

instance PrettyAnn (XtorSig a) where
  prettyAnn (MkXtorSig xt args) = prettyAnn xt <> prettyAnn args

instance PrettyAnn (TypeScheme pol) where
  prettyAnn (TypeScheme [] ty) = prettyAnn ty
  prettyAnn (TypeScheme tvs ty) =
    annKeyword "forall" <+>
    intercalateX " " (map prettyAnn tvs) <>
    "." <+>
    prettyAnn ty

instance PrettyAnn (Constraint a) where
  prettyAnn (SubType _ t1 t2) =
    prettyAnn t1 <+> "<:" <+> prettyAnn t2

instance PrettyAnn TypeName where
  prettyAnn (MkTypeName tn) = annTypeName (pretty tn)

---------------------------------------------------------------------------------
-- Prettyprinting of Declarations
---------------------------------------------------------------------------------

instance PrettyAnn DataCodata where
  prettyAnn Data = annKeyword "data"
  prettyAnn Codata = annKeyword "codata"

instance PrettyAnn DataDecl where
  prettyAnn (NominalDecl tn dc xtors) =
    prettyAnn dc <+>
    prettyAnn tn <+>
    braces (mempty <+> cat (punctuate " , " (prettyAnn <$> xtors)) <+> mempty) <>
    semi

instance PrettyAnn a => PrettyAnn (Declaration a) where
  prettyAnn (PrdDecl _ fv tm) =
    annKeyword "prd" <+> pretty fv <+> annSymbol ":=" <+> prettyAnn tm <> semi
  prettyAnn (CnsDecl _ fv tm) =
    annKeyword "cns" <+> pretty fv <+> annSymbol ":=" <+> prettyAnn tm <> semi
  prettyAnn (CmdDecl _ fv cm) =
    annKeyword "cmd" <+> pretty fv <+> annSymbol ":=" <+> prettyAnn cm <> semi
  prettyAnn (DefDecl _ fv tm) =
    annKeyword "def" <+> pretty fv <+> annSymbol ":=" <+> prettyAnn tm <> semi
  prettyAnn (DataDecl _ decl) = prettyAnn decl

instance PrettyAnn (NamedRep (Declaration FreeVarName)) where
  prettyAnn (NamedRep (PrdDecl _ fv tm)) =
    annKeyword "prd" <+> pretty fv <+> annSymbol ":=" <+> prettyAnn (openSTermComplete tm) <> semi
  prettyAnn (NamedRep (CnsDecl _ fv tm)) =
    annKeyword "cns" <+> pretty fv <+> annSymbol ":=" <+> prettyAnn (openSTermComplete tm) <> semi
  prettyAnn (NamedRep (CmdDecl _ fv cm)) =
    annKeyword "cmd" <+> pretty fv <+> annSymbol ":=" <+> prettyAnn (openCommandComplete cm) <> semi
  prettyAnn (NamedRep (DefDecl _ fv tm)) =
    annKeyword "def" <+> pretty fv <+> annSymbol ":=" <+> prettyAnn (openATermComplete tm) <> semi
  prettyAnn (NamedRep (DataDecl _ decl)) = prettyAnn decl

instance {-# OVERLAPPING #-} PrettyAnn [Declaration FreeVarName] where
  prettyAnn decls = vsep (prettyAnn . NamedRep <$> decls)

---------------------------------------------------------------------------------
-- Prettyprinting of Environments
---------------------------------------------------------------------------------

instance PrettyAnn (Environment bs) where
  prettyAnn Environment { prdEnv, cnsEnv, cmdEnv, defEnv, declEnv } =
    vsep [ppPrds, "", ppCns, "", ppCmds, "",  ppDefs, "", ppDecls, ""]
    where
      ppPrds = vsep $ "Producers:" : ( (\(v,(_,ty)) -> pretty v <+> ":" <+> prettyAnn ty) <$> (M.toList prdEnv))
      ppCns  = vsep $ "Consumers:" : ( (\(v,(_,ty)) -> pretty v <+> ":" <+> prettyAnn ty) <$> (M.toList cnsEnv))
      ppCmds = vsep $ "Commands" : ( (\(v,_) -> pretty v) <$> (M.toList cmdEnv))
      ppDefs = vsep $ "Definitions:" : ( (\(v,(_,ty)) -> pretty v <+> ":" <+> prettyAnn ty) <$> (M.toList defEnv))
      ppDecls = vsep $ "Type declarations:" : (prettyAnn <$> declEnv)

---------------------------------------------------------------------------------
-- Prettyprinting of Errors
---------------------------------------------------------------------------------

instance PrettyAnn Error where
  prettyAnn (ParseError err) = "Parsing error:" <+> pretty err
  prettyAnn (EvalError err) = "Evaluation error:" <+> pretty err
  prettyAnn (GenConstraintsError err) = "Constraint generation error:" <+> pretty err
  prettyAnn (SolveConstraintsError err) = "Constraint solving error:" <+> pretty err
  prettyAnn (TypeAutomatonError err) = "Type simplification error:" <+> pretty err
  prettyAnn (OtherError err) = "Other Error:" <+> pretty err

instance PrettyAnn Pos where
  prettyAnn p = pretty (unPos p)

instance PrettyAnn Loc where
  prettyAnn (Loc (SourcePos fp line1 column1) (SourcePos _ line2 column2)) =
    pretty fp <> ":" <> prettyAnn line1 <> ":" <> prettyAnn column1 <> "-" <> prettyAnn line2 <> ":" <> prettyAnn column2

instance PrettyAnn LocatedError where
  prettyAnn (Located loc err) = vsep ["Error at:" <+> prettyAnn loc, prettyAnn err]

