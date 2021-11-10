module Pretty.STerms where

import Prettyprinter

import Pretty.Pretty
import Syntax.STerms
import Syntax.CommonTerm
---------------------------------------------------------------------------------
-- Asymmetric Terms
---------------------------------------------------------------------------------


instance PrettyAnn (ACase ext) where
  prettyAnn MkACase{ acase_name, acase_args, acase_term } =
    prettyAnn acase_name <>
    parens (intercalateComma (prettyAnn <$> acase_args)) <+>
    annSymbol "=>" <+>
    prettyAnn acase_term

instance PrettyAnn (ATerm ext) where
  prettyAnn (Dtor _ xt t args) =
    parens ( prettyAnn t <> "." <> prettyAnn xt <> parens (intercalateComma (map prettyAnn args)))
  prettyAnn (Match _ t cases) =
    annKeyword "match" <+>
    prettyAnn t <+>
    annKeyword "with" <+>
    braces (group (nest 3 (line' <> vsep (punctuate comma (prettyAnn <$> cases)))))
  prettyAnn (Comatch _ cocases) =
    annKeyword "comatch" <+>
    braces (group (nest 3 (line' <> vsep (punctuate comma (prettyAnn <$> cocases)))))

instance PrettyAnn (NamedRep (ATerm ext)) where
  prettyAnn (NamedRep tm) = prettyAnn (openATermComplete tm)

---------------------------------------------------------------------------------
-- Symmetric Terms
---------------------------------------------------------------------------------

instance PrettyAnn (SCase ext) where
  prettyAnn MkSCase{..} =
    prettyAnn scase_name <>
    prettyTwice scase_args <+>
    annSymbol "=>" <+>
    prettyAnn scase_cmd

instance PrettyAnn (XtorArgs ext) where
  prettyAnn (MkXtorArgs prds cns) = prettyTwice' prds cns

isNumSTerm :: STerm pc ext -> Maybe Int
isNumSTerm (XtorCall _ PrdRep (MkXtorName Nominal "Z") (MkXtorArgs [] [])) = Just 0
isNumSTerm (XtorCall _ PrdRep (MkXtorName Nominal "S") (MkXtorArgs [n] [])) = case isNumSTerm n of
  Nothing -> Nothing
  Just n -> Just (n + 1)
isNumSTerm _ = Nothing

instance PrettyAnn (STerm pc ext) where
  prettyAnn (isNumSTerm -> Just n) = pretty n
  prettyAnn (BoundVar _ _ (i,j)) = parens (pretty i <> "," <> pretty j)
  prettyAnn (FreeVar _ _ v) = pretty v
  prettyAnn (XtorCall _ _ xt args) = prettyAnn xt <> prettyAnn args
  prettyAnn (XMatch _ PrdRep _ cases) =
    annKeyword "comatch" <+>
    braces (group (nest 3 (line' <> vsep (punctuate comma (prettyAnn <$> cases)))))
  prettyAnn (XMatch _ CnsRep _ cases) =
    annKeyword "match"   <+>
    braces (group (nest 3 (line' <> vsep (punctuate comma (prettyAnn <$> cases)))))
  prettyAnn (MuAbs _ pc a cmd) =
    annKeyword (case pc of {PrdRep -> "mu"; CnsRep -> "mu"}) <+>
    prettyAnn a <> "." <> parens (prettyAnn cmd)

instance PrettyAnn (Command ext) where
  prettyAnn (Done _)= annKeyword "Done"
  prettyAnn (Print _ t) = annKeyword "Print" <> parens (prettyAnn t)
  prettyAnn (Apply _ t1 t2) = group (nest 3 (line' <> vsep [prettyAnn t1, annSymbol ">>", prettyAnn t2]))

instance PrettyAnn (NamedRep (STerm pc ext)) where
  prettyAnn (NamedRep tm) = prettyAnn (openSTermComplete tm)

instance PrettyAnn (NamedRep (Command ext)) where
  prettyAnn (NamedRep cmd) = prettyAnn (openCommandComplete cmd)

