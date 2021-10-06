module TypeAutomata.RemoveAdmissible
  ( removeAdmissableFlowEdges
  ) where

import Syntax.CommonTerm (PrdCns(..))
import Syntax.Types
import TypeAutomata.Definition

import Data.Graph.Inductive.Graph

import Control.Applicative ((<|>))
import Control.Monad (guard, forM_)

import Data.List (delete, find)
import Data.Tuple (swap)
import Data.Maybe (isJust)
import qualified Data.Set as S

----------------------------------------------------------------------------------------
-- Removal of admissible flow edges.
--
-- The removal of admissible flow edges is part of the type simplification process.
-- In our representation of type automata, a type variable is represented by a flow edge
-- connecting two nodes. For example, "forall a. a -> a" is represented as
--
--            ----------------
--       -----| { Ap(_)[_] } |------
--       |    ----------------     |
--       |                         |
--       |Ap(1)                    |Ap[1]
--       |                         |
--   ----------        a       ----------
--   |        |~~~~~~~~~~~~~~~~|        |
--   ----------                ----------
--
--  But in some cases the flow edge is admissible. Consider the following automaton:
--
--            ----------------
--       -----| { Ap(_)[_] } |------
--       |    ----------------     |
--       |                         |
--       |Ap(1)                    |Ap[1]
--       |                         |
--   ----------        a       ----------
--   | Int    |~~~~~~~~~~~~~~~~|  Int   |
--   ----------                ----------
--
-- This automaton would be turned into the type "forall a. a /\ Int -> a \/ Int".
-- The admissibility check below recognizes that the flow edge "a" can be removed,
-- which results in the following automaton.
--
--            ----------------
--       -----| { Ap(_)[_] } |------
--       |    ----------------     |
--       |                         |
--       |Ap(1)                    |Ap[1]
--       |                         |
--   ----------                ----------
--   | Int    |                |  Int   |
--   ----------                ----------
--
-- This automaton is rendered as the (simpler) type "Int -> Int".
--
----------------------------------------------------------------------------------------

sucWith :: TypeGr -> Node -> EdgeLabelNormal -> Maybe Node
sucWith gr i el = lookup el (map swap (lsuc gr i))

subtypeData :: TypeAutCore EdgeLabelNormal -> FlowEdge -> Maybe ()
subtypeData aut@TypeAutCore{ ta_gr } (i,j) = do
  (MkNodeLabel Neg (Just dat1) _ _ _) <- lab ta_gr i
  (MkNodeLabel Pos (Just dat2) _ _ _) <- lab ta_gr j
  -- Check that all constructors in dat1 are also in dat2.
  forM_ (S.toList dat1) $ \xt -> guard (xt `S.member` dat2)
  -- Check arguments of each constructor of dat1.
  forM_ (labelName <$> S.toList dat1) $ \xt -> do
    forM_ [(n,el) | (n, el@(EdgeSymbol Data xt' Prd _)) <- lsuc ta_gr i, xt == xt'] $ \(n,el) -> do
      m <- sucWith ta_gr j el
      admissableM aut (n,m)
    forM_ [(n,el) | (n, el@(EdgeSymbol Data xt' Cns _)) <- lsuc ta_gr i, xt == xt'] $ \(n,el) -> do
      m <- sucWith ta_gr j el
      admissableM aut (m,n)

subtypeCodata :: TypeAutCore EdgeLabelNormal -> FlowEdge -> Maybe ()
subtypeCodata aut@TypeAutCore{ ta_gr } (i,j) = do
  (MkNodeLabel Neg _ (Just codat1) _ _) <- lab ta_gr i
  (MkNodeLabel Pos _ (Just codat2) _ _) <- lab ta_gr j
  -- Check that all destructors of codat2 are also in codat1.
  forM_ (S.toList codat2) $ \xt -> guard (xt `S.member` codat1)
  -- Check arguments of all destructors of codat2.
  forM_ (labelName <$> S.toList codat2) $ \xt -> do
    forM_ [(n,el) | (n, el@(EdgeSymbol Codata xt' Prd _)) <- lsuc ta_gr i, xt == xt'] $ \(n,el) -> do
      m <- sucWith ta_gr j el
      admissableM aut (m,n)
    forM_ [(n,el) | (n, el@(EdgeSymbol Codata xt' Cns _)) <- lsuc ta_gr i, xt == xt'] $ \(n,el) -> do
      m <- sucWith ta_gr j el
      admissableM aut (n,m)

subtypeNominal :: TypeAutCore EdgeLabelNormal -> FlowEdge -> Maybe ()
subtypeNominal TypeAutCore{ ta_gr } (i,j) = do
  (MkNodeLabel Neg _ _ nominal1 _) <- lab ta_gr i
  (MkNodeLabel Pos _ _ nominal2 _) <- lab ta_gr j
  guard $ not . S.null $ S.intersection nominal1 nominal2

-- Require at least one common type name in ref type set for which the two structural refinements fulfil
-- subtypeData/subtypeCodata
subtypeRefined :: TypeAutCore EdgeLabelNormal -> FlowEdge -> Maybe ()
subtypeRefined aut@TypeAutCore{ ta_gr } (i,j) = do
  (MkNodeLabel Neg _ _ _ tyNames1) <- lab ta_gr i
  (MkNodeLabel Pos _ _ _ tyNames2) <- lab ta_gr j
  let (_,_,_,iOuts) = context ta_gr i
  let (_,_,_,jOuts) = context ta_gr j
  guard (not . S.null $ S.intersection tyNames1 tyNames2) -- Check for common type names
  forM_ (S.intersection tyNames1 tyNames2) (\tn -> do -- For all common type names:
    (_, ref1) <- find (\case (RefineEdge tn', _) -> tn'==tn; _ -> False) iOuts
    (_, ref2) <- find (\case (RefineEdge tn', _) -> tn'==tn; _ -> False) jOuts
    admissableM aut (ref1,ref2)
    -- Check subtyping relation between corresponding structural refinements
    )

admissableM :: TypeAutCore EdgeLabelNormal -> FlowEdge -> Maybe ()
admissableM aut@TypeAutCore{..} e =
  guard (e `elem` ta_flowEdges) <|>
    subtypeData aut e <|>
    subtypeCodata aut e <|>
    subtypeNominal aut e <|>
    subtypeRefined aut e

-- this version of admissability check also accepts if the edge under consideration is in the set of known flow edges
-- needs to be seperated for technical reasons...
admissable :: TypeAutCore EdgeLabelNormal -> FlowEdge -> Bool
admissable aut@TypeAutCore {..} e = isJust $ admissableM (aut { ta_flowEdges = delete e ta_flowEdges }) e

removeAdmissableFlowEdges :: TypeAutDet pol -> TypeAutDet pol
removeAdmissableFlowEdges aut@TypeAut{ ta_core = tac@TypeAutCore {..}} =
  aut { ta_core = tac { ta_flowEdges = filter (not . admissable tac) ta_flowEdges }}
