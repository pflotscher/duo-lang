module TypeAutomata.FromAutomaton ( autToType ) where

import Syntax.Terms
import Syntax.Types
import Syntax.TypeGraph
import Utils
import TypeAutomata.FlowAnalysis

import Control.Monad.Reader
import Data.Maybe (fromJust)

import Data.Functor.Identity
import Data.Set (Set)
import qualified Data.Set as S

import Data.Map (Map)
import qualified Data.Map as M

import Data.Graph.Inductive.Graph
import Data.Graph.Inductive.Query.DFS (dfs)

--------------------------------------------------------------------------
-- Type automata -> Target types
--------------------------------------------------------------------------

autToType :: TypeAutDet -> TypeScheme
autToType aut@TypeAut{..} =
  let
    mp = getFlowAnalysisMap aut
    monotype = runReader (autToTypeReader mp (runIdentity ta_starts)) (ta_gr, S.empty)
    tvars = S.toList $ S.unions (M.elems mp)
  in
    TypeScheme tvars monotype

autToTypeReader :: Map Node (Set TVar) -> Node -> Reader (TypeGr, Set Node) TargetType
autToTypeReader tvMap i = do
  (gr,cache) <- ask
  let (_,_,(pol,HeadCons datSet codatSet),outs) = context gr i
  let (maybeDat,maybeCodat) = (S.toList <$> datSet, S.toList <$> codatSet)
  -- highestIndex :: DataOrCodata -> XtorName -> PrdOrCns -> Int
  let highestIndex s xt pc = maximum ((-1) : [j | (EdgeSymbol _ _ _ j, _) <- filter (\(EdgeSymbol s' xt' pc' _, _) -> s==s' && xt==xt' && pc==pc') outs])
  if i `S.member` cache
    then return $ TTyRVar (MkRVar ("r" ++ show i))
    else do
      resType <- local (\(gr0,cache0) ->
          (delEdges [(i,n) | n <- suc gr i, i `elem` dfs [n] gr] gr0
          ,S.insert i cache0)) $ do
        let varL = TTyTVar <$> (S.toList $ fromJust $ M.lookup i tvMap)
        datL <- case maybeDat of
          {Nothing -> return [] ;
          Just xtors -> do
            sig <- forM xtors $ \xt -> do
              prdTypes <- forM [0..highestIndex Data xt Prd] $ \j -> do
                typs <- sequence [autToTypeReader tvMap n | (EdgeSymbol Data xt' Prd j', n) <- outs, xt == xt', j == j']
                return $ unionOrInter (applyVariance Data Prd pol) typs
              cnsTypes <- forM [0..highestIndex Data xt Cns] $ \j -> do
                typs <- sequence [autToTypeReader tvMap n | (EdgeSymbol Data xt' Cns j', n) <- outs, xt == xt', j == j']
                return $ unionOrInter (applyVariance Data Cns pol) typs
              return (MkXtorSig xt (Twice prdTypes cnsTypes))
            return [TTySimple Data sig]}
        codatL <- case maybeCodat of
          {Nothing -> return [] ;
          Just xtors -> do
            sig <- forM xtors $ \xt -> do
              prdTypes <- forM [0..highestIndex Codata xt Prd] $ \j -> do
                typs <- sequence [autToTypeReader tvMap n | (EdgeSymbol Codata xt' Prd j', n) <- outs, xt == xt', j == j']
                return $ unionOrInter (applyVariance Codata Prd pol) typs
              cnsTypes <- forM [0..highestIndex Codata xt Cns] $ \j -> do
                typs <- sequence [autToTypeReader tvMap n | (EdgeSymbol Codata xt' Cns j', n) <- outs, xt == xt', j == j']
                return $ unionOrInter (applyVariance Codata Cns pol) typs
              return (MkXtorSig xt (Twice prdTypes cnsTypes))
            return [TTySimple Codata sig]}
        return $ unionOrInter pol (varL ++ datL ++ codatL)

      -- If the graph is cyclic, make a recursive type
      if i `elem` dfs (suc gr i) gr
        then return $ TTyRec (MkRVar ("r" ++ show i)) resType
        else return resType
