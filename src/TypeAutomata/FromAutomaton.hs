{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use tuple-section" #-}

module TypeAutomata.FromAutomaton ( autToType ) where

import Syntax.TST.Types
import Syntax.RST.Types (PolarityRep(..), flipPolarityRep)
import Syntax.CST.Types qualified as CST
import Syntax.CST.Types (PrdCns(..), PrdCnsRep(..))
import Syntax.CST.Names
import Syntax.CST.Kinds
import Pretty.TypeAutomata ()
import TypeAutomata.Definition
import TypeAutomata.BicliqueDecomp
import Utils ( enumerate )
import Loc ( defaultLoc )

import Control.Monad.Except
import Control.Monad.Reader

import Errors
import Data.Maybe (fromJust)
import Data.Functor.Identity
import Data.Set (Set)
import Data.Set qualified as S
import Data.Map (Map)
import Data.Map qualified as M
import Data.Text qualified as T
import Data.Graph.Inductive.Graph
import Data.Graph.Inductive.Query.DFS (dfs)
import Data.List.NonEmpty (NonEmpty((:|)))


-- | Generate a graph consisting only of the flow_edges of the type automaton.
genFlowGraph :: TypeAutCore a -> FlowGraph
genFlowGraph TypeAutCore{..} = mkGraph [(n,()) | n <- nodes ta_gr] [(i,j,()) | (i,j) <- ta_flowEdges]

initializeFromAutomaton :: TypeAutDet pol -> AutToTypeState
initializeFromAutomaton TypeAut{..} =
  let
    flowAnalysis = computeFlowMap (genFlowGraph ta_core )

    gr = ta_gr ta_core
    getTVars :: (Node,Set SkolemTVar) -> [KindedSkolem]
    getTVars (nd,skolems) = do
      let skList = S.toList skolems
      let nl = lab gr nd
      let mk = case nl of Nothing -> error "Can't find Node Label (should never happen)"; Just nl -> getKindNL nl
      map (\x -> (x,mk)) skList
  in
    AutToTypeState { tvMap = flowAnalysis
                   , graph = gr
                   , cache = S.empty
                   , tvars = concatMap getTVars (M.toList flowAnalysis)
                   --S.toList $ S.unions (M.elems flowAnalysis)
                   }

--------------------------------------------------------------------------
-- Type automata -> Types
--------------------------------------------------------------------------

data AutToTypeState = AutToTypeState { tvMap :: Map Node (Set SkolemTVar)
                                     , graph :: TypeGr
                                     , cache :: Set Node
                                     , tvars :: [KindedSkolem]
                                     }
type AutToTypeM a = (ReaderT AutToTypeState (Except (NonEmpty Error))) a

runAutToTypeM :: AutToTypeM a -> AutToTypeState -> Either (NonEmpty Error) a
runAutToTypeM m state = runExcept (runReaderT m state)


autToType :: TypeAutDet pol -> Either (NonEmpty Error) (TypeScheme pol)
autToType aut@TypeAut{..} = do
  let startState = initializeFromAutomaton aut
  monotype <- runAutToTypeM (nodeToType ta_pol (runIdentity ta_starts)) startState
  pure TypeScheme { ts_loc = defaultLoc
                  -- TODO Replace CBV with actual kinds
                  , ts_vars = tvars startState
                  , ts_monotype = monotype
                  }

visitNode :: Node -> AutToTypeState -> AutToTypeState
visitNode i aut@AutToTypeState { graph, cache } =
  aut { graph = delEdges [(i,n) | n <- suc graph i, i `elem` dfs [n] graph] graph
      , cache = S.insert i cache }

checkCache :: Node -> AutToTypeM Bool
checkCache i = do
  cache <- asks cache
  return (i `S.member` cache)

getNodeKind :: Node -> AutToTypeM MonoKind
getNodeKind i = do
  gr <- asks graph
  case lab gr i of
    Nothing -> throwAutomatonError  defaultLoc [T.pack ("Could not find Nodelabel of Node" <> show i)]
    Just (MkNodeLabel _ _ _ _ _ _ mk) -> return (CBox mk)
    Just (MkPrimitiveNodeLabel _ primTy) ->
      case primTy of
        I64 -> return I64Rep
        F64 -> return F64Rep
        PChar -> return CharRep
        PString -> return StringRep



nodeToTVars :: PolarityRep pol -> Node -> AutToTypeM [Typ pol]
nodeToTVars rep i = do
  tvMap <- asks tvMap
  knd <- getNodeKind i
  return (TySkolemVar defaultLoc rep knd <$> S.toList (fromJust $ M.lookup i tvMap))

nodeToOuts :: Node -> AutToTypeM [(EdgeLabelNormal, Node)]
nodeToOuts i = do
  gr <- asks graph
  let (_,_,_,outs) = context gr i
  return outs

-- | Compute the Nodes which have to be turned into the argument types for one constructor or destructor.
computeArgNodes :: [(EdgeLabelNormal, Node)] -- ^ All the outgoing edges of a node.
                -> CST.DataCodata -- ^ Whether we want to construct a constructor or destructor
                -> XtorLabel -- ^ The Label of the constructor / destructor
                -> [(PrdCns,[Node])] -- ^ The nodes which contain the arguments of the constructor / destructor
computeArgNodes outs dc MkXtorLabel { labelName, labelArity } = args
  where
    argFun (n,pc) = (pc, [ node | (EdgeSymbol dc' xt pc' pos, node) <- outs, dc' == dc, xt == labelName, pc == pc', pos == n])
    args = argFun <$> enumerate labelArity


-- | Takes the output of computeArgNodes and turns the nodes into types.
argNodesToArgTypes :: [(PrdCns,[Node])] -> PolarityRep pol -> AutToTypeM (LinearContext pol)
argNodesToArgTypes argNodes rep = do
  forM argNodes $ \ns -> do
    case ns of
      (Prd, ns) -> do
         typs <- forM ns (nodeToType rep)
         knd <- checkTypKinds typs
         pure $ PrdCnsType PrdRep $ case rep of
                                       PosRep -> mkUnion defaultLoc knd typs
                                       NegRep -> mkInter defaultLoc knd typs
      (Cns, ns) -> do
         typs <- forM ns (nodeToType (flipPolarityRep rep))
         knd <- checkTypKinds typs
         pure $ PrdCnsType CnsRep $ case rep of
                                       PosRep -> mkInter defaultLoc knd typs
                                       NegRep -> mkUnion defaultLoc knd typs

checkTypKinds :: [Typ pol] -> AutToTypeM MonoKind
checkTypKinds [] = throwAutomatonError  defaultLoc [T.pack "Can't get Kind of empty list of types"]
checkTypKinds (fst:rst) =
  let knd = getKind fst
  in if all ((knd ==) . getKind) rst then return knd else throwAutomatonError defaultLoc [T.pack "Kinds of intersection types don't match"]

nodeToType :: PolarityRep pol -> Node -> AutToTypeM (Typ pol)
nodeToType rep i = do
  -- First we check if i is in the cache.
  -- If i is in the cache, we return a recursive variable.
  inCache <- checkCache i
  if inCache
    then do 
      knd <- getNodeKind i
      pure (TyRecVar defaultLoc rep knd (MkRecTVar ("r" <> T.pack (show i))))
    else nodeToTypeNoCache rep i

-- | Should only be called if node is not in cache.
nodeToTypeNoCache :: PolarityRep pol -> Node -> AutToTypeM (Typ pol)
nodeToTypeNoCache rep i  = do
  gr <- asks graph
  knd <- getNodeKind i
  case fromJust (lab gr i) of
    MkPrimitiveNodeLabel _ tp -> do
      let toPrimType :: PolarityRep pol -> PrimitiveType -> Typ pol
          toPrimType rep I64 = TyI64 defaultLoc rep
          toPrimType rep F64 = TyF64 defaultLoc rep
          toPrimType rep PChar = TyChar defaultLoc rep
          toPrimType rep PString = TyString defaultLoc rep
      pure (toPrimType rep tp)
    MkNodeLabel _ datSet codatSet tns refDat refCodat _ -> do
      outs <- nodeToOuts i
      let (maybeDat,maybeCodat) = (S.toList <$> datSet, S.toList <$> codatSet)
      let refDatTypes = M.toList refDat -- Unique data ref types
      let refCodatTypes = M.toList refCodat -- Unique codata ref types
      resType <- local (visitNode i) $ do
        -- Creating type variables
        varL <- nodeToTVars rep i
        -- Creating data types
        datL <- case maybeDat of
          Nothing -> return []
          Just xtors -> do
            sig <- forM xtors $ \xt -> do
              let nodes = computeArgNodes outs CST.Data xt
              argTypes <- argNodesToArgTypes nodes rep
              return (MkXtorSig (labelName xt) argTypes)
            return [TyData defaultLoc rep knd sig]
        -- Creating codata types
        codatL <- case maybeCodat of
          Nothing -> return []
          Just xtors -> do
            sig <- forM xtors $ \xt -> do
              let nodes = computeArgNodes outs CST.Codata xt
              argTypes <- argNodesToArgTypes nodes (flipPolarityRep rep)
              return (MkXtorSig (labelName xt) argTypes)
            return [TyCodata defaultLoc rep knd sig]
        -- Creating ref data types
        refDatL <- do
          forM refDatTypes $ \(tn,xtors) -> do
            sig <- forM (S.toList xtors) $ \xt -> do
              let nodes = computeArgNodes outs CST.Data xt
              argTypes <- argNodesToArgTypes nodes rep
              return (MkXtorSig (labelName xt) argTypes)
            return $ TyDataRefined defaultLoc rep knd tn sig
        -- Creating ref codata types
        refCodatL <- do
          forM refCodatTypes $ \(tn,xtors) -> do
            sig <- forM (S.toList xtors) $ \xt -> do
              let nodes = computeArgNodes outs CST.Codata xt
              argTypes <- argNodesToArgTypes nodes (flipPolarityRep rep)
              return (MkXtorSig (labelName xt) argTypes)
            return $ TyCodataRefined defaultLoc rep knd tn sig
        -- Creating Nominal types
        let adjEdges = lsuc gr i
        let typeArgsMap :: Map (RnTypeName, Int) (Node, Variance) = M.fromList [((tn, i), (node,var)) | (node, TypeArgEdge tn var i) <- adjEdges]
        let unsafeLookup :: (RnTypeName, Int) -> AutToTypeM (Node,Variance) = \k -> case M.lookup k typeArgsMap of
              Just x -> pure x
              Nothing -> throwOtherError defaultLoc ["Impossible: Cannot loose type arguments in automata"]
        nominals <- do
            forM (S.toList tns) $ \(tn, variances) -> do
              argNodes <- sequence [ unsafeLookup (tn, i) | i <- [0..(length variances - 1)]]
              let f (node, Covariant) = CovariantType <$> nodeToType rep node
                  f (node, Contravariant) = ContravariantType <$> nodeToType (flipPolarityRep rep) node
              args <- mapM f argNodes 
              polyknd <- getPolyKnd knd args 
              case args of 
                [] -> pure $ TyNominal defaultLoc rep polyknd tn
                (fst:rst) -> pure $ TyApp defaultLoc rep (TyNominal defaultLoc rep polyknd tn) (fst:|rst)

        let typs = varL ++ datL ++ codatL ++ refDatL ++ refCodatL ++ nominals -- ++ prims
        return $ case rep of
          PosRep -> mkUnion defaultLoc knd typs
          NegRep -> mkInter defaultLoc knd typs

      -- If the graph is cyclic, make a recursive type
      if i `elem` dfs (suc gr i) gr
        then return $ TyRec defaultLoc rep (MkRecTVar ("r" <> T.pack (show i))) resType
        else return resType
      where 
        getPolyKnd :: MonoKind -> [VariantType pol] -> AutToTypeM PolyKind
        getPolyKnd (CBox ev) args = do 
          let args' = zip args [1..length args-1]
          return $ MkPolyKind (map argToKindArg args') ev
        getPolyKnd _ _ = throwOtherError defaultLoc ["Nominal Type can only have CBV or CBN as kind"]
        argToKindArg :: (VariantType pol,Int) -> (Variance, SkolemTVar, MonoKind)
        argToKindArg (ContravariantType ty, n) = 
          (Contravariant, MkSkolemTVar $ "a" <> T.pack (show n),getKind ty)
        argToKindArg (CovariantType ty, n) = 
          (Covariant, MkSkolemTVar $ "a" <> T.pack (show n), getKind ty)
