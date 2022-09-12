module TypeInference.GenerateConstraints.Kinds where

import Syntax.TST.Program qualified as TST
import Syntax.RST.Program qualified as RST
import Syntax.RST.Types qualified as RST
import Syntax.TST.Types qualified as TST
import Syntax.CST.Kinds
import Syntax.CST.Names 
import Lookup
import Errors
import Loc
import Pretty.Pretty
import TypeInference.GenerateConstraints.Definition

import Control.Monad.State
import Data.Map qualified as M
import Data.Text qualified as T
import Data.Bifunctor (bimap)

--------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------
getXtorKinds :: Loc -> [RST.XtorSig pol] -> GenM MonoKind
getXtorKinds loc [] = throwSolverError loc ["Can't find kinds of empty List of Xtors"]
getXtorKinds _ [xtor] = do 
  let nm = RST.sig_name xtor
  lookupXtorKind nm
getXtorKinds loc (fst:rst) = do
  let nm = RST.sig_name fst
  knd <- lookupXtorKind nm
  knd' <- getXtorKinds loc rst
  if knd == knd' then
    return knd 
  else 
    throwSolverError loc ["Kinds ", ppPrint knd , " and ", ppPrint knd', "of constructors do not match"]

getTyNameKind ::  Loc -> RnTypeName -> GenM MonoKind
getTyNameKind loc tyn = do
  decl <- lookupTypeName loc tyn
  getKindDecl decl
  
getKindDecl ::  TST.DataDecl -> GenM MonoKind
getKindDecl decl = do
  let polyknd = TST.data_kind decl
  return (CBox (returnKind polyknd))

newKVar :: GenM KVar
newKVar = do
  kvCnt <- gets kVarCount
  modify (\gs@GenerateState{} -> gs { kVarCount = kvCnt + 1 })
  return (MkKVar (T.pack ("kv" <> show kvCnt)))

--------------------------------------------------------------------------------------------
-- Annotating Data Declarations 
--------------------------------------------------------------------------------------------
-- we can't use the environment here, as the results are inserted into the environment

-- only temporary, will be removed 
defaultKind :: MonoKind
defaultKind = CBox CBV

annotXtor :: PolyKind -> RST.XtorSig pol -> TST.XtorSig pol
annotXtor polyknd (RST.MkXtorSig nm ctxt) = TST.MkXtorSig nm (annotCtxt polyknd ctxt)

annotCtxt :: PolyKind -> RST.LinearContext pol -> TST.LinearContext pol
annotCtxt _ [] = []
annotCtxt polyknd (RST.PrdCnsType pc ty:rst) = TST.PrdCnsType pc (annotTy polyknd ty) : annotCtxt polyknd rst

annotVarTys :: PolyKind -> [RST.VariantType pol] ->[TST.VariantType pol]
annotVarTys _ [] = [] 
annotVarTys polyknd (RST.CovariantType ty:rst) = TST.CovariantType (annotTy polyknd ty) : annotVarTys polyknd rst
annotVarTys polyknd (RST.ContravariantType ty:rst) = TST.ContravariantType (annotTy polyknd ty) : annotVarTys polyknd rst



--data PolyKind =
--  MkPolyKind { kindArgs :: [(Variance, SkolemTVar, MonoKind)]
--             , returnKind :: EvaluationOrder
--             }
getKindSkolem :: PolyKind -> SkolemTVar -> MonoKind
getKindSkolem polyknd = searchKindArgs (kindArgs polyknd)
  where 
    searchKindArgs :: [(Variance, SkolemTVar, MonoKind)] -> SkolemTVar -> MonoKind
    searchKindArgs [] _ = error "Skolem Variable not found in argument types of polykind"
    searchKindArgs ((_,tv,mk):rst) tv' = if tv == tv' then mk else searchKindArgs rst tv'

annotTy :: PolyKind -> RST.Typ pol -> TST.Typ pol
annotTy polyknd (RST.TySkolemVar loc pol tv) = TST.TySkolemVar loc pol (getKindSkolem polyknd tv) tv 
-- uni vars should not appear in data declarations
annotTy _ RST.TyUniVar{} = error "UniVar should not appear in data declaration"
annotTy polyknd (RST.TyRecVar loc pol tv) = TST.TyRecVar loc pol defaultKind tv
annotTy polyknd (RST.TyData loc pol xtors) =  TST.TyData loc pol defaultKind (map (annotXtor polyknd) xtors)
annotTy polyknd (RST.TyCodata loc pol xtors) = TST.TyCodata loc pol defaultKind (map (annotXtor polyknd) xtors)
annotTy polyknd (RST.TyDataRefined loc pol tyn xtors) =  TST.TyDataRefined loc pol defaultKind tyn (map (annotXtor polyknd) xtors)
annotTy polyknd (RST.TyCodataRefined loc pol tyn xtors) = TST.TyCodataRefined loc pol defaultKind tyn  (map (annotXtor polyknd) xtors)
annotTy polyknd (RST.TyNominal loc pol tyn vartys) = TST.TyNominal loc pol defaultKind tyn (annotVarTys polyknd vartys)
annotTy polyknd (RST.TySyn loc pol tyn ty) =  TST.TySyn loc pol tyn (annotTy polyknd ty)
annotTy polyknd (RST.TyBot loc) = TST.TyBot loc defaultKind
annotTy polyknd (RST.TyTop loc) = TST.TyTop loc defaultKind
annotTy polyknd (RST.TyUnion loc ty1 ty2) = TST.TyUnion loc defaultKind (annotTy polyknd ty1) (annotTy polyknd ty2)
annotTy polyknd (RST.TyInter loc ty1 ty2) = TST.TyInter loc defaultKind (annotTy polyknd ty1) (annotTy polyknd ty2)
annotTy polyknd (RST.TyRec loc pol tv ty) = TST.TyRec loc pol tv (annotTy polyknd ty)
annotTy polyknd (RST.TyI64 loc pol) = TST.TyI64 loc pol
annotTy polyknd (RST.TyF64 loc pol) = TST.TyF64 loc pol
annotTy polyknd (RST.TyChar loc pol) = TST.TyChar loc pol
annotTy polyknd (RST.TyString loc pol) = TST.TyString loc pol
annotTy polyknd (RST.TyFlipPol pol ty) = TST.TyFlipPol pol (annotTy polyknd ty)


annotateDataDecl :: RST.DataDecl -> TST.DataDecl 
annotateDataDecl RST.NominalDecl {
  data_loc = loc, 
  data_doc = doc,
  data_name = tyn,
  data_polarity = pol,
  data_kind = polyknd,
  data_xtors = xtors 
  } = 
    TST.NominalDecl { 
        data_loc = loc, 
        data_doc = doc,
        data_name = tyn,
        data_polarity = pol,
        data_kind = polyknd,
        data_xtors = Data.Bifunctor.bimap (map (annotXtor polyknd)) (map (annotXtor polyknd)) xtors
      }
annotateDataDecl RST.RefinementDecl { 
  data_loc = loc, 
  data_doc = doc,
  data_name = tyn,
  data_polarity = pol ,
  data_refinement_empty = empt,
  data_refinement_full = ful,
  data_kind = polyknd,
  data_xtors = xtors,
  data_xtors_refined = xtorsref
  } = 
    TST.RefinementDecl {
      data_loc = loc,
      data_doc = doc,
      data_name = tyn,
      data_polarity = pol ,
      data_refinement_empty = Data.Bifunctor.bimap (annotTy polyknd) (annotTy polyknd) empt,
      data_refinement_full = Data.Bifunctor.bimap (annotTy polyknd) (annotTy polyknd) ful, 
      data_kind = polyknd,
      data_xtors = Data.Bifunctor.bimap (map (annotXtor polyknd)) (map (annotXtor polyknd)) xtors,
      data_xtors_refined = Data.Bifunctor.bimap (map (annotXtor polyknd)) (map (annotXtor polyknd)) xtorsref
      }

--------------------------------------------------------------------------------------------
-- checking Kinds
--------------------------------------------------------------------------------------------

annotateInstDecl ::  (RST.Typ RST.Pos, RST.Typ RST.Neg) -> GenM (TST.Typ RST.Pos, TST.Typ RST.Neg)
annotateInstDecl (ty1, ty2) = do 
  ty1' <- annotateTyp ty1
  ty2' <- annotateTyp ty2
  return (ty1', ty2')

annotateMaybeTypeScheme ::  Maybe (RST.TypeScheme pol) -> GenM (Maybe (TST.TypeScheme pol))
annotateMaybeTypeScheme Nothing = return Nothing 
annotateMaybeTypeScheme (Just ty) = do
  ty' <- annotateTypeScheme ty 
  return (Just ty')

annotateTypeScheme ::  RST.TypeScheme pol -> GenM (TST.TypeScheme pol)
annotateTypeScheme RST.TypeScheme {ts_loc = loc, ts_vars = tvs, ts_monotype = ty} = do
  ty' <- annotateTyp ty
  return TST.TypeScheme {ts_loc = loc, ts_vars = tvs, ts_monotype = ty'}

annotateVariantType ::  RST.VariantType pol -> GenM (TST.VariantType pol)
annotateVariantType (RST.CovariantType ty) = TST.CovariantType <$> annotateTyp ty
annotateVariantType (RST.ContravariantType ty) = TST.ContravariantType <$> annotateTyp ty

annotatePrdCnsType ::  RST.PrdCnsType pol -> GenM (TST.PrdCnsType pol)
annotatePrdCnsType (RST.PrdCnsType rep ty) = do 
  ty' <- annotateTyp ty
  return (TST.PrdCnsType rep ty')

annotateLinearContext ::  RST.LinearContext pol -> GenM (TST.LinearContext pol)
annotateLinearContext = mapM annotatePrdCnsType

annotateXtorSig ::  RST.XtorSig pol -> GenM (TST.XtorSig pol)
annotateXtorSig RST.MkXtorSig { sig_name = nm, sig_args = ctxt } = do 
  ctxt' <- annotateLinearContext ctxt 
  return (TST.MkXtorSig {sig_name = nm, sig_args = ctxt' })

annotateTyp ::  RST.Typ pol -> GenM (TST.Typ pol)
annotateTyp (RST.TySkolemVar loc pol tv) = do
  skMap <- gets usedSkolemVars
  case M.lookup tv skMap of 
    Nothing -> do
      kv <- newKVar
      let newM = M.insert tv (KindVar kv) skMap
      modify (\gs@GenerateState{} -> gs { usedSkolemVars = newM })
      return (TST.TySkolemVar loc pol (KindVar kv) tv)
    Just mk -> return (TST.TySkolemVar loc pol mk tv)

annotateTyp (RST.TyUniVar loc pol tv) = do 
  uniMap <- gets usedUniVars
  case M.lookup tv uniMap of 
    Nothing -> do
      kv <- newKVar
      let newM = M.insert tv (KindVar kv) uniMap
      modify (\gs@GenerateState{} -> gs { usedUniVars = newM })
      return (TST.TyUniVar loc pol (KindVar kv) tv)
    Just mk -> return (TST.TyUniVar loc pol mk tv)

annotateTyp (RST.TyRecVar loc pol rv) = do
  rvMap <- gets usedRecVars
  case M.lookup rv rvMap of 
    Nothing -> do
      kv <- newKVar 
      let newM = M.insert rv (KindVar kv) rvMap
      modify (\gs@GenerateState{} -> gs { usedRecVars = newM })
      return (TST.TyRecVar loc pol (KindVar kv) rv)
    Just mk -> return (TST.TyRecVar loc pol mk rv)

annotateTyp (RST.TyData loc pol xtors) = do 
  knd <- getXtorKinds loc xtors 
  xtors' <- mapM annotateXtorSig xtors
  return (TST.TyData loc pol knd xtors')

annotateTyp (RST.TyCodata loc pol xtors) = do 
  knd <- getXtorKinds loc xtors
  xtors' <- mapM annotateXtorSig xtors
  return (TST.TyCodata loc pol knd xtors')

annotateTyp (RST.TyDataRefined loc pol tyn xtors) = do 
  xtors' <- mapM annotateXtorSig xtors
  knd <- getTyNameKind loc tyn
  return (TST.TyDataRefined loc pol knd tyn xtors')

annotateTyp (RST.TyCodataRefined loc pol tyn xtors) = do
  xtors' <- mapM annotateXtorSig xtors
  knd <- getTyNameKind loc tyn
  return (TST.TyCodataRefined loc pol knd tyn xtors')

annotateTyp (RST.TyNominal loc pol tyn vartys) = do
  vartys' <- mapM annotateVariantType vartys
  knd <- getTyNameKind loc tyn
  return (TST.TyNominal loc pol knd tyn vartys')

annotateTyp (RST.TySyn loc pol tn ty) = do 
  ty' <- annotateTyp ty 
  return (TST.TySyn loc pol tn ty')

annotateTyp (RST.TyBot loc) = TST.TyBot loc . KindVar <$> newKVar

annotateTyp (RST.TyTop loc) = TST.TyTop loc . KindVar <$> newKVar

annotateTyp (RST.TyUnion loc ty1 ty2) = do 
  ty1' <- annotateTyp ty1
  ty2' <- annotateTyp ty2
  kv <- newKVar 
  return (TST.TyUnion loc (KindVar kv) ty1' ty2')
  
annotateTyp (RST.TyInter loc ty1 ty2) = do
  ty1' <- annotateTyp ty1
  ty2' <- annotateTyp ty2
  kv <- newKVar 
  return (TST.TyInter loc (KindVar kv) ty1' ty2')
  
annotateTyp (RST.TyRec loc pol rv ty) = do
  ty' <- annotateTyp ty
  return (TST.TyRec loc pol rv ty')

annotateTyp (RST.TyI64 loc pol) = return (TST.TyI64 loc pol)
annotateTyp (RST.TyF64 loc pol) = return (TST.TyF64 loc pol)
annotateTyp (RST.TyChar loc pol) = return (TST.TyChar loc pol)
annotateTyp (RST.TyString loc pol) = return(TST.TyString loc pol)

annotateTyp (RST.TyFlipPol pol ty) = do 
  ty' <- annotateTyp ty
  return (TST.TyFlipPol pol ty')


