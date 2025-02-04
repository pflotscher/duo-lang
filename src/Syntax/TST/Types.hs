module Syntax.TST.Types where

import Data.Set (Set)
import Data.Set qualified as S
import Data.Map (Map)
import Data.Map qualified as M
import Data.List.NonEmpty (NonEmpty)
import Data.Maybe (fromMaybe)
import Data.Kind ( Type )
import Syntax.RST.Types (Polarity(..), PolarityRep(..), FlipPol ,PrdCnsFlip)
import Syntax.CST.Kinds
import Syntax.CST.Types ( PrdCnsRep(..), PrdCns(..), Arity)
import Syntax.CST.Names ( MethodName, RecTVar, RnTypeName, SkolemTVar, UniTVar, XtorName )

import Loc

------------------------------------------------------------------------------
-- CovContraList
------------------------------------------------------------------------------

data VariantType (pol :: Polarity) where
  CovariantType :: Typ pol -> VariantType pol
  ContravariantType :: Typ (FlipPol pol) -> VariantType pol

deriving instance Eq (VariantType pol)
deriving instance Ord (VariantType pol)
deriving instance Show (VariantType pol)

toVariance :: VariantType pol -> Variance
toVariance (CovariantType _) = Covariant
toVariance (ContravariantType _) = Contravariant

------------------------------------------------------------------------------
-- LinearContexts
------------------------------------------------------------------------------

data PrdCnsType (pol :: Polarity) where
  PrdCnsType :: PrdCnsRep pc -> Typ (PrdCnsFlip pc pol) -> PrdCnsType pol

instance Eq (PrdCnsType pol) where
  (PrdCnsType PrdRep ty1) == (PrdCnsType PrdRep ty2) = ty1 == ty2
  (PrdCnsType CnsRep ty1) == (PrdCnsType CnsRep ty2) = ty1 == ty2
  _ == _ = False

instance Ord (PrdCnsType pol) where
  (PrdCnsType PrdRep ty1) `compare` (PrdCnsType PrdRep ty2) = ty1 `compare` ty2
  (PrdCnsType CnsRep ty1) `compare` (PrdCnsType CnsRep ty2) = ty1 `compare` ty2
  (PrdCnsType PrdRep _)   `compare` (PrdCnsType CnsRep _)   = LT
  (PrdCnsType CnsRep _)   `compare` (PrdCnsType PrdRep _)   = GT

instance Show (PrdCnsType pol) where
  show (PrdCnsType PrdRep ty) = "PrdType " <> show ty
  show (PrdCnsType CnsRep ty) = "CnsType " <> show ty

type LinearContext pol = [PrdCnsType pol]

linearContextToArity :: LinearContext pol -> Arity
linearContextToArity = map f
  where
    f :: PrdCnsType pol -> PrdCns
    f (PrdCnsType PrdRep _) = Prd
    f (PrdCnsType CnsRep _) = Cns

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

data XtorSig (pol :: Polarity) = MkXtorSig
  { sig_name :: XtorName
  , sig_args :: LinearContext pol
  }

deriving instance Eq (XtorSig pol)
deriving instance Ord (XtorSig pol)
deriving instance Show (XtorSig pol)

data MethodSig (pol :: Polarity) = MkMethodSig
  { msig_name :: MethodName
  , msig_args :: [PrdCnsType pol]
  }

deriving instance Eq (MethodSig pol)
deriving instance Ord (MethodSig pol)
deriving instance Show (MethodSig pol)


data Typ (pol :: Polarity) where
  TySkolemVar     :: Loc -> PolarityRep pol -> MonoKind -> SkolemTVar -> Typ pol
  TyUniVar        :: Loc -> PolarityRep pol -> MonoKind -> UniTVar -> Typ pol
  TyRecVar        :: Loc -> PolarityRep pol -> MonoKind -> RecTVar -> Typ pol
  -- | We have to duplicate TyStructData and TyStructCodata here due to restrictions of the deriving mechanism of Haskell.
  -- | Refinement types are represented by the presence of the TypeName parameter
  TyData          :: Loc -> PolarityRep pol -> MonoKind                  -> [XtorSig pol]           -> Typ pol
  TyCodata        :: Loc -> PolarityRep pol -> MonoKind                  -> [XtorSig (FlipPol pol)] -> Typ pol
  TyDataRefined   :: Loc -> PolarityRep pol -> MonoKind   -> RnTypeName  -> [XtorSig pol]           -> Typ pol
  TyCodataRefined :: Loc -> PolarityRep pol -> MonoKind   -> RnTypeName  -> [XtorSig (FlipPol pol)] -> Typ pol
  -- | Nominal types with arguments to type parameters (contravariant, covariant)
  TyNominal       :: Loc -> PolarityRep pol -> PolyKind -> RnTypeName -> Typ pol
  TyApp           :: Loc -> PolarityRep pol -> Typ pol -> NonEmpty (VariantType pol) -> Typ pol
  -- | Type synonym
  TySyn           :: Loc -> PolarityRep pol -> RnTypeName -> Typ pol -> Typ pol
  -- | Lattice types
  TyBot           :: Loc -> MonoKind -> Typ Pos
  TyTop           :: Loc -> MonoKind -> Typ Neg
  TyUnion         :: Loc -> MonoKind -> Typ Pos -> Typ Pos -> Typ Pos
  TyInter         :: Loc -> MonoKind -> Typ Neg -> Typ Neg -> Typ Neg
  -- | Equirecursive Types
  TyRec           :: Loc -> PolarityRep pol -> RecTVar -> Typ pol -> Typ pol
  -- | Builtin Types
  TyI64           :: Loc -> PolarityRep pol -> Typ pol
  TyF64           :: Loc -> PolarityRep pol -> Typ pol
  TyChar          :: Loc -> PolarityRep pol -> Typ pol
  TyString        :: Loc -> PolarityRep pol -> Typ pol
  -- | TyFlipPol is only generated during focusing, and cannot be parsed!
  TyFlipPol       :: PolarityRep pol -> Typ (FlipPol pol) -> Typ pol

deriving instance Eq (Typ pol)
deriving instance Ord (Typ pol)
deriving instance Show (Typ pol)

mkUnion :: Loc -> MonoKind -> [Typ Pos] -> Typ Pos
mkUnion loc mk   []     = TyBot loc mk
mkUnion _   _   [t]    = t
mkUnion loc knd (t:ts) = TyUnion loc knd t (mkUnion loc knd ts)

mkInter :: Loc -> MonoKind -> [Typ Neg] -> Typ Neg
mkInter loc mk   []     = TyTop loc mk
mkInter _   _   [t]    = t
mkInter loc knd (t:ts) = TyInter loc knd t (mkInter loc knd ts)

getPolarity :: Typ pol -> PolarityRep pol
getPolarity (TySkolemVar _ rep _ _)        = rep
getPolarity (TyUniVar _ rep _ _)           = rep
getPolarity (TyRecVar _ rep _ _)           = rep
getPolarity (TyData _ rep _  _)            = rep
getPolarity (TyCodata _ rep _  _)          = rep
getPolarity (TyDataRefined _ rep  _ _ _)   = rep
getPolarity (TyCodataRefined _ rep  _ _ _) = rep
getPolarity (TyNominal _ rep _ _)          = rep
getPolarity (TyApp _ rep _ _)              = rep
getPolarity (TySyn _ rep _ _)              = rep
getPolarity TyTop {}                       = NegRep
getPolarity TyBot {}                       = PosRep
getPolarity TyUnion {}                     = PosRep
getPolarity TyInter {}                     = NegRep
getPolarity (TyRec _ rep _ _)              = rep
getPolarity (TyI64 _ rep)                  = rep
getPolarity (TyF64 _ rep)                  = rep
getPolarity (TyChar _ rep)                 = rep
getPolarity (TyString _ rep)               = rep
getPolarity (TyFlipPol rep _)              = rep

class GetKind (a :: Type) where
  getKind :: a -> MonoKind

instance GetKind (Typ pol) where 
  getKind (TySkolemVar _ _ mk _)        = mk
  getKind (TyUniVar _ _ mk _)           = mk
  getKind (TyRecVar _ _ mk _)           = mk
  getKind (TyData _ _ mk _ )            = mk
  getKind (TyCodata _ _ mk _ )          = mk
  getKind (TyDataRefined _ _ mk _ _ )   = mk
  getKind (TyCodataRefined _ _ mk _ _ ) = mk
  getKind (TyNominal _ _ pk _ )         = CBox $ returnKind pk
  getKind (TyApp _ _ ty _)              = getKind ty
  getKind (TySyn _ _ _ ty)              = getKind ty
  getKind (TyTop _ mk)                  = mk
  getKind (TyBot _ mk)                  = mk
  getKind (TyUnion _ mk _ _)            = mk
  getKind (TyInter _ mk _ _)            = mk
  getKind (TyRec _ _ _ ty)              = getKind ty
  getKind TyI64{}                       = I64Rep
  getKind TyF64{}                       = F64Rep
  getKind TyChar{}                      = CharRep
  getKind TyString{}                    = StringRep
  getKind (TyFlipPol _ ty)              = getKind ty

instance GetKind (PrdCnsType pol) where 
  getKind (PrdCnsType _ ty) = getKind ty

instance GetKind (VariantType pol) where 
  getKind (CovariantType ty) = getKind ty 
  getKind (ContravariantType ty) = getKind ty


------------------------------------------------------------------------------
-- Type Schemes
------------------------------------------------------------------------------

data TypeScheme (pol :: Polarity) = TypeScheme
  { ts_loc :: Loc
  , ts_vars :: [KindedSkolem]
  , ts_monotype :: Typ pol
  }

deriving instance Eq (TypeScheme Pos)
deriving instance Eq (TypeScheme Neg)
deriving instance Ord (TypeScheme Pos)
deriving instance Ord (TypeScheme Neg)
deriving instance Show (TypeScheme Pos)
deriving instance Show (TypeScheme Neg)

data TopAnnot (pol :: Polarity) where
  Annotated :: TypeScheme pol -> TopAnnot pol
  Inferred  :: TypeScheme pol -> TopAnnot pol

deriving instance Show (TopAnnot Pos)
deriving instance Show (TopAnnot Neg)


-- | Typeclass for computing free type variables
class FreeTVars (a :: Type) where
  freeTVars :: a -> Set (SkolemTVar, MonoKind)

instance FreeTVars (Typ pol) where
  freeTVars (TySkolemVar _ _ knd tv)         = S.singleton (tv,knd)
  freeTVars TyRecVar{}                       = S.empty
  freeTVars TyUniVar{}                       = S.empty
  freeTVars TyTop {}                         = S.empty
  freeTVars TyBot {}                         = S.empty
  freeTVars (TyUnion _ _ ty ty')             = S.union (freeTVars ty) (freeTVars ty')
  freeTVars (TyInter _ _ ty ty')             = S.union (freeTVars ty) (freeTVars ty')
  freeTVars (TyRec _ _ _ t)                  = freeTVars t
  --freeTVars (TyNominal _ _ _ _ args)         = S.unions (freeTVars <$> args)
  freeTVars TyNominal{}                      = S.empty
  freeTVars (TyApp _ _ ty args)              = S.union (freeTVars ty) (S.unions (freeTVars <$> args))
  freeTVars (TySyn _ _ _ ty)                 = freeTVars ty
  freeTVars (TyData _  _ _ xtors)            = S.unions (freeTVars <$> xtors)
  freeTVars (TyCodata _ _ _ xtors)           = S.unions (freeTVars <$> xtors)
  freeTVars (TyDataRefined _ _ _ _ xtors)    = S.unions (freeTVars <$> xtors)
  freeTVars (TyCodataRefined  _ _ _ _ xtors) = S.unions (freeTVars <$> xtors)
  freeTVars (TyI64 _ _)                      = S.empty
  freeTVars (TyF64 _ _)                      = S.empty
  freeTVars (TyChar _ _)                     = S.empty
  freeTVars (TyString _ _)                   = S.empty
  freeTVars (TyFlipPol _ ty)                 = freeTVars ty

instance FreeTVars (PrdCnsType pol) where
  freeTVars (PrdCnsType _ ty) = freeTVars ty

instance FreeTVars (VariantType pol) where
  freeTVars (CovariantType ty)     = freeTVars ty
  freeTVars (ContravariantType ty) = freeTVars ty

instance FreeTVars (LinearContext pol) where
  freeTVars ctxt = S.unions (freeTVars <$> ctxt)

instance FreeTVars (XtorSig pol) where
  freeTVars MkXtorSig { sig_args } = freeTVars sig_args

-- | Generalize over all free type variables of a type.
generalize :: Typ pol -> TypeScheme pol
generalize ty = TypeScheme defaultLoc (S.toList $ freeTVars ty) ty

------------------------------------------------------------------------------
-- Bisubstitution and Zonking
------------------------------------------------------------------------------

data VarType
  = UniVT
  | SkolemVT
  | RecVT

type family BisubstMap (vt :: VarType) :: Type where
  BisubstMap UniVT    = (Map UniTVar (Typ Pos, Typ Neg), Map KVar MonoKind)
  BisubstMap SkolemVT = Map SkolemTVar (Typ Pos, Typ Neg)
  BisubstMap RecVT    = Map RecTVar (Typ Pos, Typ Neg)

newtype Bisubstitution vt = MkBisubstitution { bisubst_map :: BisubstMap vt }

data VarTypeRep (vt :: VarType) where
  UniRep    :: VarTypeRep UniVT
  SkolemRep :: VarTypeRep SkolemVT
  RecRep    :: VarTypeRep RecVT

-- | Class of types for which a Bisubstitution can be applied.
class Zonk (a :: Type) where
  zonk :: VarTypeRep vt -> Bisubstitution vt -> a -> a

instance Zonk (Typ pol) where
  zonk UniRep bisubst ty@(TyUniVar _ PosRep _ tv) = 
    case M.lookup tv (fst (bisubst_map bisubst)) of
      Nothing -> zonkKind bisubst ty 
      Just (tyPos,_) -> zonkKind bisubst tyPos
  zonk UniRep bisubst ty@(TyUniVar _ NegRep _ tv) = 
    case M.lookup tv (fst (bisubst_map bisubst)) of
      Nothing -> zonkKind bisubst ty
      Just (_,tyNeg) -> zonkKind bisubst tyNeg
  zonk SkolemRep _ ty@TyUniVar{} = ty
  zonk RecRep _ ty@TyUniVar{} = ty
  zonk UniRep bisubst ty@TySkolemVar{} = zonkKind bisubst ty
  zonk SkolemRep bisubst ty@(TySkolemVar _ PosRep _ tv) = case M.lookup tv (bisubst_map bisubst) of
     Nothing -> ty -- Recursive variable!
     Just (tyPos,_) -> tyPos
  zonk SkolemRep bisubst ty@(TySkolemVar _ NegRep _ tv) = case M.lookup tv (bisubst_map bisubst) of
     Nothing -> ty -- Recursive variable!
     Just (_,tyNeg) -> tyNeg
  zonk RecRep _ ty@TySkolemVar{} = ty
  zonk UniRep bisubst ty@TyRecVar{} = zonkKind bisubst ty
  zonk SkolemRep _ ty@TyRecVar{} = ty
  zonk RecRep bisubst ty@(TyRecVar _ PosRep _ tv) = case M.lookup tv (bisubst_map bisubst) of
    Nothing -> ty
    Just (tyPos,_) -> tyPos
  zonk RecRep bisubst ty@(TyRecVar _ NegRep _ tv) = case M.lookup tv (bisubst_map bisubst) of
    Nothing -> ty
    Just (_,tyNeg) -> tyNeg
  zonk UniRep bisubst (TyData loc rep mk xtors) =
     TyData loc rep (zonkKind bisubst mk) (zonk UniRep bisubst <$> xtors)
  zonk vt bisubst (TyData loc rep mk xtors) =
     TyData loc rep  mk (zonk vt bisubst <$> xtors)
  zonk UniRep bisubst (TyCodata loc rep mk xtors) =
     TyCodata loc rep (zonkKind bisubst mk) (zonk UniRep bisubst <$> xtors)
  zonk vt bisubst (TyCodata loc rep mk xtors) =
     TyCodata loc rep mk (zonk vt bisubst <$> xtors)
  zonk UniRep bisubst (TyDataRefined loc rep mk tn xtors) =
     TyDataRefined loc rep (zonkKind bisubst mk) tn (zonk UniRep bisubst <$> xtors)
  zonk vt bisubst (TyDataRefined loc rep mk tn xtors) =
     TyDataRefined loc rep mk tn (zonk vt bisubst <$> xtors)
  zonk UniRep bisubst (TyCodataRefined loc rep mk tn xtors) =
     TyCodataRefined loc rep (zonkKind bisubst mk) tn (zonk UniRep bisubst <$> xtors)
  zonk vt bisubst (TyCodataRefined loc rep mk tn xtors) =
     TyCodataRefined loc rep mk tn (zonk vt bisubst <$> xtors)
  zonk UniRep bisubst (TyNominal loc rep knd tn) = 
    TyNominal loc rep (zonkKind bisubst knd) tn 
  zonk _ _ (TyNominal loc rep kind tn) =
     TyNominal loc rep kind tn 
  zonk vt bisubst (TyApp loc rep ty args) = 
    TyApp loc rep (zonk vt bisubst ty) (zonk vt bisubst <$> args)
  zonk vt bisubst (TySyn loc rep nm ty) =
     TySyn loc rep nm (zonk vt bisubst ty)
  zonk UniRep bisubst (TyTop loc mk) = TyTop loc (zonkKind bisubst mk)
  zonk _vt _ (TyTop loc mk) =
    TyTop loc mk
  zonk UniRep bisubst (TyBot loc mk) = TyBot loc (zonkKind bisubst mk)
  zonk _vt _ (TyBot loc mk) =
    TyBot loc mk
  zonk UniRep bisubst (TyUnion loc knd ty1 ty2) = 
    TyUnion loc (zonkKind bisubst knd) (zonk UniRep bisubst ty1) (zonk UniRep bisubst ty2)
  zonk vt bisubst (TyUnion loc knd ty ty') =
    TyUnion loc knd (zonk vt bisubst ty) (zonk vt bisubst ty')
  zonk UniRep bisubst (TyInter loc knd ty1 ty2) = 
    TyInter loc (zonkKind bisubst knd) (zonk UniRep bisubst ty1) (zonk UniRep bisubst ty2)
  zonk vt bisubst (TyInter loc knd ty ty') =
    TyInter loc knd (zonk vt bisubst ty) (zonk vt bisubst ty')
  zonk RecRep bisubst (TyRec loc rep tv ty) =
    let bisubst' = MkBisubstitution $ M.delete tv (bisubst_map bisubst)
    in TyRec loc rep tv $ zonk RecRep bisubst' ty
  zonk vt bisubst (TyRec loc rep tv ty) =
     TyRec loc rep tv (zonk vt bisubst ty)
  zonk _vt _ t@TyI64 {} = t
  zonk _vt _ t@TyF64 {} = t
  zonk _vt _ t@TyChar {} = t
  zonk _vt _ t@TyString {} = t
  zonk vt bisubst (TyFlipPol rep ty) = TyFlipPol rep (zonk vt bisubst ty)

instance Zonk (VariantType pol) where
  zonk vt bisubst (CovariantType ty) = CovariantType (zonk vt bisubst ty)
  zonk vt bisubst (ContravariantType ty) = ContravariantType (zonk vt bisubst ty)

instance Zonk (XtorSig pol) where
  zonk vt bisubst (MkXtorSig name ctxt) =
    MkXtorSig name (zonk vt bisubst ctxt)

instance Zonk (LinearContext pol) where
  zonk vt bisubst = fmap (zonk vt bisubst)

instance Zonk (PrdCnsType pol) where
  zonk vt bisubst (PrdCnsType rep ty) = PrdCnsType rep (zonk vt bisubst ty)

instance Zonk (TypeScheme pol) where 
  zonk UniRep bisubst (TypeScheme {ts_loc = loc, ts_vars = tvars, ts_monotype = ty}) =
    TypeScheme {ts_loc = loc, ts_vars = map (zonkKind bisubst) tvars, ts_monotype = zonk UniRep bisubst ty}
  zonk _ _ _ = error "Not implemented"

class ZonkKind (a::Type) where 
  zonkKind :: Bisubstitution UniVT -> a -> a

instance ZonkKind MonoKind where 
  zonkKind _ (CBox cc) = CBox cc
  zonkKind _ F64Rep = F64Rep 
  zonkKind _ I64Rep = I64Rep
  zonkKind _ CharRep = CharRep
  zonkKind _ StringRep = StringRep
  zonkKind bisubst kindV@(KindVar kv) = Data.Maybe.fromMaybe kindV (M.lookup kv (snd (bisubst_map bisubst)))

instance ZonkKind PolyKind where 
  zonkKind bisubst (MkPolyKind args eval) = 
    MkPolyKind (map (\(x,y,z) -> (x,y, zonkKind bisubst z)) args) eval 

instance ZonkKind (Typ pol) where 
  zonkKind bisubst (TySkolemVar loc rep mk tv) = 
    TySkolemVar loc rep (zonkKind bisubst mk) tv
  zonkKind bisubst (TyUniVar loc rep mk tv) = 
    TyUniVar loc rep (zonkKind bisubst mk) tv
  zonkKind bisubst (TyRecVar loc rep mk tv) =
    TyRecVar loc rep (zonkKind bisubst mk) tv
  zonkKind bisubst (TyData loc pol mk xtors) =
    TyData loc pol (zonkKind bisubst mk) (zonkKind bisubst xtors)
  zonkKind bisubst (TyCodata loc pol mk xtors) = 
    TyCodata loc pol (zonkKind bisubst mk) (zonkKind bisubst xtors)
  zonkKind bisubst (TyDataRefined loc pol mk tyn xtors)=
    TyDataRefined loc pol (zonkKind bisubst mk) tyn (zonkKind bisubst xtors)
  zonkKind bisubst (TyCodataRefined loc pol mk tyn xtors) = 
    TyCodataRefined loc pol (zonkKind bisubst mk) tyn (zonkKind bisubst xtors)
  zonkKind bisubst (TyNominal loc pol mk tyn) =
    TyNominal loc pol (zonkKind bisubst mk) tyn
  zonkKind bisubst (TyApp loc pol ty args) =
    TyApp loc pol (zonkKind bisubst ty) (zonkKind bisubst <$> args)
  zonkKind bisubst (TySyn loc pol tyn ty) =
    TySyn loc pol tyn (zonkKind bisubst ty)
  zonkKind bisubst (TyTop loc mk) = 
    TyTop loc (zonkKind bisubst mk)
  zonkKind bisubst (TyBot loc mk) = 
    TyBot loc (zonkKind bisubst mk)
  zonkKind bisubst (TyUnion loc mk ty1 ty2) =
    TyUnion loc (zonkKind bisubst mk) (zonkKind bisubst ty1) (zonkKind bisubst ty2)
  zonkKind bisubst (TyInter loc mk ty1 ty2) =
    TyInter loc (zonkKind bisubst mk) (zonkKind bisubst ty1) (zonkKind bisubst ty2)
  zonkKind bisubst (TyRec loc pol rv ty) = 
    TyRec loc pol rv (zonkKind bisubst ty)
  zonkKind _ ty@TyI64{} = ty
  zonkKind _ ty@TyF64{} = ty
  zonkKind _ ty@TyChar{} = ty
  zonkKind _ ty@TyString{} = ty
  zonkKind bisubst (TyFlipPol pol ty) = TyFlipPol pol (zonkKind bisubst ty)

instance ZonkKind [XtorSig pol] where 
  zonkKind bisubst = map (zonkKind bisubst)

instance ZonkKind (XtorSig pol) where 
  zonkKind bisubst (MkXtorSig { sig_name = nm, sig_args = args }) = 
    MkXtorSig {sig_name = nm, sig_args = zonkKind bisubst args}
 
instance ZonkKind (LinearContext pol) where 
  zonkKind bisubst = map (zonkKind bisubst)

instance ZonkKind (PrdCnsType pol) where 
  zonkKind bisubst (PrdCnsType rep ty) = PrdCnsType rep (zonkKind bisubst ty)
 
instance ZonkKind [VariantType pol] where 
  zonkKind bisubst = map (zonkKind bisubst)

instance ZonkKind (VariantType pol) where 
  zonkKind bisubst (CovariantType ty) = CovariantType (zonkKind bisubst ty)
  zonkKind bisubst (ContravariantType ty) = ContravariantType (zonkKind bisubst ty)

instance ZonkKind KindedSkolem where 
  zonkKind bisubst (sk,mk) = (sk, zonkKind bisubst mk)

-- This is probably not 100% correct w.r.t alpha-renaming. Postponed until we have a better repr. of types.
unfoldRecType :: Typ pol -> Typ pol
unfoldRecType recty@(TyRec _ PosRep var ty) = zonk RecRep (MkBisubstitution (M.fromList [(var,(recty, error "unfoldRecType"))])) ty
unfoldRecType recty@(TyRec _ NegRep var ty) = zonk RecRep (MkBisubstitution (M.fromList [(var,(error "unfoldRecType", recty))])) ty
unfoldRecType ty = ty
