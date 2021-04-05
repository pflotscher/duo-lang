{-# LANGUAGE OverloadedStrings #-}
module Pretty.TypeAutomata ( typeAutToDot ) where

import Data.Graph.Inductive.Graph
import Data.GraphViz.Attributes.Complete (Attribute(Style), StyleName(Dashed), StyleItem(SItem))
import Data.GraphViz
import Data.Maybe (catMaybes)
import qualified Data.Set as S
import Data.Text.Lazy (pack)
import Prettyprinter

import Pretty.Pretty (ppPrint, PrettyAnn(..), intercalateX)
import Pretty.Types ()
import Syntax.CommonTerm (PrdCns(..))
import Syntax.TypeAutomaton
import Syntax.Types


---------------------------------------------------------------------------------
-- Prettyprinting of Type Automata
---------------------------------------------------------------------------------

instance PrettyAnn XtorLabel where
  prettyAnn MkXtorLabel { labelName, labelPrdArity, labelCnsArity } =
    prettyAnn labelName <>
    parens (pretty labelPrdArity) <>
    brackets (pretty labelCnsArity)

instance PrettyAnn NodeLabel where
  prettyAnn (HeadCons _ maybeDat maybeCodat tns) = intercalateX ";" (catMaybes [printDat <$> maybeDat
                                                                          , printCodat <$> maybeCodat
                                                                          , printNominal tns])
    where
      printDat   dat   = angles (mempty <+> cat (punctuate " | " (prettyAnn <$> (S.toList dat))) <+> mempty)
      printCodat codat = braces (mempty <+> cat (punctuate " , " (prettyAnn <$> (S.toList codat))) <+> mempty)
      printNominal tns = Just (intercalateX ";" (prettyAnn <$> (S.toList tns)))

instance PrettyAnn (EdgeLabel a) where
  prettyAnn (EdgeSymbol _ xt Prd i) = prettyAnn xt <> parens (pretty i)
  prettyAnn (EdgeSymbol _ xt Cns i) = prettyAnn xt <> brackets (pretty i)
  prettyAnn (EpsilonEdge _) = "e"

typeAutToDot :: TypeAut' EdgeLabelNormal f pol -> DotGraph Node
typeAutToDot TypeAut {..} =
    let
      grWithFlow = insEdges [(i,j,EpsilonEdge ()) | (i,j) <- ta_flowEdges] (emap embedEdgeLabel ta_gr) -- Should be modified!
    in
      graphToDot typeAutParams grWithFlow

typeAutParams :: GraphvizParams Node NodeLabel EdgeLabelEpsilon () NodeLabel
typeAutParams = defaultParams
  { fmtNode = \(_,nl) ->
    [ style filled
    , fillColor $ case hc_pol nl of {Pos -> White; Neg -> Gray}
    , textLabel (pack (ppPrint (nl :: NodeLabel)))]
  , fmtEdge = \(_,_,elM) -> case elM of
                              el@(EdgeSymbol _ _ _ _) -> regularEdgeStyle el
                              (EpsilonEdge _) -> flowEdgeStyle
  }
  where
    flowEdgeStyle = [arrowTo dotArrow, Style [SItem Dashed []]]
    regularEdgeStyle el = [textLabel $ pack (ppPrint el)]
