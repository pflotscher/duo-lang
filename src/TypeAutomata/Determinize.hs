module TypeAutomata.Determinize ( determinize ) where

import Control.Monad.State
    ( execState, State, MonadState(get), modify )
import Data.Functor.Identity ( Identity(Identity) )
import Data.Graph.Inductive.Graph
    ( Node, lab, lsuc, out, Graph(mkGraph) )
import Data.Graph.Inductive.PatriciaTree ( Gr )
import Data.Map (Map)
import Data.Map qualified as M
import Data.Set (Set)
import Data.Set qualified as S
import Data.List.NonEmpty (NonEmpty(..))
import Data.Maybe (mapMaybe, fromMaybe)
import Data.Foldable (foldl')

import TypeAutomata.Definition
import Utils (intersections)
import Syntax.RST.Types ( Polarity(Neg, Pos) )

---------------------------------------------------------------------------------------
-- First step of determinization:
-- Compute the new transition function for the determinized graph,
-- using the powerset construction.
---------------------------------------------------------------------------------------

-- | A transition function for the powerset construction
type TransFun = Map (Set Node) [(Set Node, EdgeLabelNormal)]

-- | Collect all (unique) outgoing edgelabels from the given set of nodes.
getAlphabetForNodes :: Gr NodeLabel EdgeLabelNormal -> Set Node -> [EdgeLabelNormal]
getAlphabetForNodes gr ns = nub $ map (\(_,_,b) -> b) (concatMap (out gr) (S.toList ns))

-- | Get all successor nodes from the given set which are connected by the given edgeLabel.
succsWith :: Gr NodeLabel EdgeLabelNormal -> Set Node -> EdgeLabelNormal -> Set Node
succsWith gr ns x = S.fromList $ map fst . filter ((==x).snd) $ concatMap (lsuc gr) (S.toList ns)

determinizeState :: [Set Node]
                 -> Gr NodeLabel EdgeLabelNormal
                 -> State TransFun ()
determinizeState [] _ = pure ()
determinizeState (ns:rest) gr = do
  mp <- get
  if ns `elem` M.keys mp then determinizeState rest gr
    else do
      let alphabet = getAlphabetForNodes gr ns
      let newEdges = map (\x -> (succsWith gr ns x, x)) alphabet
      modify (M.insert ns newEdges)
      let newNodeSets = map fst newEdges
      determinizeState (newNodeSets ++ rest) gr


-- | Compute the transition function for the powerset construction.
transFun :: Gr NodeLabel EdgeLabelNormal
               -> Set Node -- ^ Starting states
               -> TransFun
transFun gr starts = execState (determinizeState [starts] gr) M.empty

type TransFunReindexed = [(Node, Set Node, [(Node, EdgeLabelNormal)])]

reIndexTransFun :: TransFun -> TransFunReindexed
reIndexTransFun transFun =
  let
    mp = [(M.findIndex nodeSet transFun, nodeSet, es) | (nodeSet,es) <- M.toList transFun]
    mp' = fmap (\(i,ns,es) -> (i,ns, fmap (\(ns',el) -> (M.findIndex ns' transFun, el)) es)) mp
  in mp'

---------------------------------------------------------------------------------------
-- Compute a new type graph from the TransFun and the old type graph.
---------------------------------------------------------------------------------------

-- | Return the combined node label for the given set of nodes.
getNewNodeLabel :: Gr NodeLabel b -> Set Node -> NodeLabel
getNewNodeLabel gr ns = combineNodeLabels $ mapMaybe (lab gr) (S.toList ns)

combineNodeLabels :: [NodeLabel] -> NodeLabel
combineNodeLabels [] = error "No Labels to combine"
combineNodeLabels [fstLabel@MkNodeLabel{}] = fstLabel
combineNodeLabels (fstLabel@MkNodeLabel{}:rs) =
  case rs_merged of
    pr@MkPrimitiveNodeLabel{} -> error ("Tried to combine primitive type" <> show pr <> " and algebraic type " <> show fstLabel)
    combLabel@MkNodeLabel{} ->
      if nl_kind combLabel == knd then 
        if nl_pol combLabel == pol then
          MkNodeLabel {
            nl_pol = pol,
            nl_data = mrgDat [xtors | MkNodeLabel _ (Just xtors) _ _ _ _ _ <- [fstLabel,combLabel]],
            nl_codata = mrgCodat [xtors | MkNodeLabel _ _ (Just xtors) _ _ _ _ <- [fstLabel,combLabel]],
            nl_nominal = S.unions [tn | MkNodeLabel _ _ _ tn _ _ _ <- [fstLabel, combLabel]],
            nl_ref_data = mrgRefDat [refs | MkNodeLabel _ _ _ _ refs _ _ <- [fstLabel, combLabel]],
            nl_ref_codata = mrgRefCodat [refs | MkNodeLabel _ _ _ _ _ refs _ <- [fstLabel, combLabel]],
            nl_kind = knd
          }
        else
          error "Tried to combine node labels of different polarity!"
    else 
      error "Tried to combine node labels of different kind"
  where
    pol = nl_pol fstLabel
    knd = nl_kind fstLabel
    mrgDat [] = Nothing
    mrgDat (xtor:xtors) = Just $ case pol of {Pos -> S.unions (xtor:xtors) ; Neg -> intersections (xtor :| xtors) }
    mrgCodat [] = Nothing
    mrgCodat (xtor:xtors) = Just $ case pol of {Pos -> intersections (xtor :| xtors); Neg -> S.unions (xtor:xtors)}
    mrgRefDat refs = case pol of
      Pos -> M.unionsWith S.union refs
      Neg -> M.unionsWith S.intersection refs
    mrgRefCodat refs = case pol of
      Pos -> M.unionsWith S.intersection refs
      Neg -> M.unionsWith S.union refs
    rs_merged = combineNodeLabels rs
combineNodeLabels [fstLabel@MkPrimitiveNodeLabel{}] = fstLabel
combineNodeLabels (fstLabel@MkPrimitiveNodeLabel{}:rs) =
  case rs_merged of
    nl@MkNodeLabel{} -> error ("Tried to combine primitive type" <> show fstLabel <> " and algebraic type" <> show nl)
    combLabel@MkPrimitiveNodeLabel{} ->
      if pl_pol combLabel == pol then
        if pl_prim combLabel == primT then
          MkPrimitiveNodeLabel pol primT
        else
          error ("Tried to combine " <> primToStr primT <> " and " <> primToStr (pl_prim combLabel))
      else
        error "Tried to combine node labels of different polarity!"
  where
    pol = pl_pol fstLabel
    primT = pl_prim fstLabel
    rs_merged = combineNodeLabels rs
    primToStr typ = case typ of {I64 -> "I64"; F64 -> "F64" ; PChar -> "Char" ; PString -> "String"}

-- | This function computes the new typegraph and the new starting state.
-- The nodes for the new typegraph are computed as the indizes of the sets of nodes in the TransFun map.
newTypeGraph :: TransFunReindexed -- ^ The transition function of the powerset construction.
             -> Gr NodeLabel EdgeLabelNormal -- ^ The old typegraph with a set of starting states.
             -> Gr NodeLabel EdgeLabelNormal -- ^ The new typegraph with one starting state.
newTypeGraph transFun gr =
  let
    nodes = fmap (\(i,ns,_) -> (i, getNewNodeLabel gr ns)) transFun
    edges = [(i,j,el) | (i,_,es) <- transFun, (j,el) <- es]
  in mkGraph nodes edges

------------------------------------------------------------------------------
-- Compute new flowEdges
------------------------------------------------------------------------------

flowEdges :: TransFunReindexed
                 -> [(Node,Node)] -- ^ Old flowedges
                 -> [(Node,Node)] -- ^ New flowedges
flowEdges transFun flowedges = nub $ concatMap reindexFlowEdge flowedges
  where
    getPartitions :: TransFunReindexed -> Map Node (Set Node) -> Map Node (Set Node)
    getPartitions tf m = foldl' (\m (n,ns,_) -> foldl' (\m n' -> M.insertWith S.union n' (S.singleton n) m) m ns) m tf

    partitionMap :: Map Node (Set Node)
    partitionMap = getPartitions transFun M.empty

    reindexFlowEdge :: (Node,Node) -> [(Node,Node)]
    reindexFlowEdge (l,r) = [ (l',r') | l' <- S.toList $ fromMaybe S.empty $ M.lookup l partitionMap,
                                        r' <- S.toList $ fromMaybe S.empty $ M.lookup r partitionMap]

------------------------------------------------------------------------------
-- Lift the determinization algorithm to type graphs.
------------------------------------------------------------------------------

determinize :: TypeAut pol -> TypeAutDet pol
determinize TypeAut{ ta_pol, ta_starts, ta_core = TypeAutCore { ta_gr, ta_flowEdges }} =
  let
    starts = S.fromList ta_starts
    newstart = M.findIndex starts newTransFun
    newTransFun = transFun ta_gr starts
    newTransFunReind = reIndexTransFun newTransFun
    newFlowEdges = flowEdges newTransFunReind ta_flowEdges
    newgr = newTypeGraph newTransFunReind ta_gr
    newCore = TypeAutCore { ta_gr = newgr, ta_flowEdges = newFlowEdges }
  in
    TypeAut { ta_pol = ta_pol, ta_starts = Identity newstart, ta_core = newCore }


