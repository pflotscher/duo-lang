module TypeInference.GenerateConstraints.Definition
  ( -- Constraint Generation Monad
    GenM
  , GenerateReader(..)
  , runGenM
    -- Generating fresh unification variables
  , freshTVar
  , freshTVars
  , freshTVarsForTypeParams
  , freshTVarsForInstance
    -- Throwing errors
  , throwGenError
    -- Looking up in context or environment
  , lookupContext
    -- Running computations in extended context or environment.
  , withContext
    -- Instantiating type schemes
  , instantiateTypeScheme
    -- Adding a constraint
  , addConstraint
    -- Other
  , PrdCnsToPol
  , foo
  , fromMaybeVar
  , prdCnsToPol
  , checkCorrectness
  , checkExhaustiveness
  , checkInstanceCoverage
  , translateXtorSigUpper
  , translateTypeUpper
  , translateXtorSigLower
  , translateTypeLower
  ) where

import Control.Monad.Except
import Control.Monad.Reader
import Control.Monad.State
import Data.Map ( Map )
import Data.Map qualified as M
import Data.Text qualified as T

import Driver.Environment
import Errors
import Lookup
import Pretty.Pretty
import Pretty.Terms ()
import Pretty.Types ()
import Syntax.Common.TypesPol
import Syntax.Common
import Syntax.RST.Program as RST
import TypeInference.Constraints
import TypeTranslation qualified as TT
import Utils

---------------------------------------------------------------------------------------------
-- GenerateState:
--
-- We use varCount for generating fresh type variables.
-- We collect all generated unification variables and constraints in a ConstraintSet.
---------------------------------------------------------------------------------------------
data GenerateState = GenerateState
  { varCount :: Int
  , constraintSet :: ConstraintSet
  }

initialConstraintSet :: ConstraintSet
initialConstraintSet = ConstraintSet { cs_constraints = [], cs_uvars = [] }

initialState :: GenerateState
initialState = GenerateState { varCount = 0, constraintSet = initialConstraintSet }

---------------------------------------------------------------------------------------------
-- GenerateReader:
--
-- We have access to a program environment and a local variable context.
-- The context contains monotypes, whereas the environment contains type schemes.
---------------------------------------------------------------------------------------------

newtype GenerateReader = GenerateReader { context :: [LinearContext Pos]
                                     }

initialReader :: Map ModuleName Environment -> (Map ModuleName Environment, GenerateReader)
initialReader env = (env, GenerateReader { context = [] })

---------------------------------------------------------------------------------------------
-- GenM
---------------------------------------------------------------------------------------------

newtype GenM a = GenM { getGenM :: ReaderT (Map ModuleName Environment, GenerateReader) (StateT GenerateState (Except Error)) a }
  deriving (Functor, Applicative, Monad, MonadState GenerateState, MonadReader (Map ModuleName Environment, GenerateReader), MonadError Error)

runGenM :: Map ModuleName Environment -> GenM a -> Either Error (a, ConstraintSet)
runGenM env m = case runExcept (runStateT (runReaderT  (getGenM m) (initialReader env)) initialState) of
  Left err -> Left err
  Right (x, state) -> Right (x, constraintSet state)

---------------------------------------------------------------------------------------------
-- Generating fresh unification variables
---------------------------------------------------------------------------------------------

freshTVar :: UVarProvenance -> GenM (Typ Pos, Typ Neg)
freshTVar uvp = do
  var <- gets varCount
  let tvar = MkTVar ("u" <> T.pack (show var))
  -- We need to increment the counter:
  modify (\gs@GenerateState{} -> gs { varCount = var + 1 })
  -- We also need to add the uvar to the constraintset.
  modify (\gs@GenerateState{ constraintSet = cs@ConstraintSet { cs_uvars } } ->
            gs { constraintSet = cs { cs_uvars = cs_uvars ++ [(tVarToUniTVar tvar, uvp)] } })
  return (TyVar defaultLoc PosRep Nothing tvar, TyVar defaultLoc NegRep Nothing tvar)

freshTVars :: [(PrdCns, Maybe FreeVarName)] -> GenM (LinearContext Pos, LinearContext Neg)
freshTVars [] = return ([],[])
freshTVars ((Prd,fv):rest) = do
  (lctxtP, lctxtN) <- freshTVars rest
  (tp, tn) <- freshTVar (ProgramVariable (fromMaybeVar fv))
  return (PrdCnsType PrdRep tp:lctxtP, PrdCnsType PrdRep tn:lctxtN)
freshTVars ((Cns,fv):rest) = do
  (lctxtP, lctxtN) <- freshTVars rest
  (tp, tn) <- freshTVar (ProgramVariable (fromMaybeVar fv))
  return (PrdCnsType CnsRep tn:lctxtP, PrdCnsType CnsRep tp:lctxtN)

freshTVarsForTypeParams :: forall pol. PolarityRep pol -> DataDecl -> GenM ([VariantType pol], Bisubstitution)
freshTVarsForTypeParams rep decl = 
  let MkPolyKind { kindArgs } = data_kind decl
      tn = data_name decl
  in freshTVarsForTypeParams' rep kindArgs (Left tn)

freshTVarsForInstance :: forall pol. PolarityRep pol -> ClassDeclaration -> GenM ([VariantType pol], Bisubstitution)
freshTVarsForInstance rep decl = 
  let kindArgs = classdecl_kinds decl
      cn = classdecl_name decl
  in freshTVarsForTypeParams' rep kindArgs (Right cn)


freshTVarsForTypeParams' :: forall pol. PolarityRep pol -> [(Variance, SkolemTVar, MonoKind)] -> Either RnTypeName ClassName -> GenM ([VariantType pol], Bisubstitution)
freshTVarsForTypeParams' rep kindArgs tn = do
  (varTypes, vars) <- freshTVars tn ((\(variance,tv,_) -> (skolemTVarToTVar tv,variance)) <$> kindArgs)
  let map = paramsMap kindArgs vars
  case rep of
    PosRep -> pure (varTypes, map)
    NegRep -> pure (varTypes, map)
  where
   freshTVars ::  Either RnTypeName ClassName -> [(TVar, Variance)] -> GenM ([VariantType pol],[(Typ Pos, Typ Neg)])
   freshTVars _ [] = pure ([],[])
   freshTVars tn ((tv,variance) : vs) = do
    (vartypes,vs') <- freshTVars tn vs
    (tyPos, tyNeg) <- freshTVar ((case tn of Left tn -> TypeParameter tn; Right cn -> TypeClassInstance cn) (tVarToUniTVar tv))
    case (variance, rep) of
      (Covariant, PosRep)     -> pure (CovariantType tyPos     : vartypes, (tyPos, tyNeg) : vs')
      (Covariant, NegRep)     -> pure (CovariantType tyNeg     : vartypes, (tyPos, tyNeg) : vs')
      (Contravariant, PosRep) -> pure (ContravariantType tyNeg : vartypes, (tyPos, tyNeg) : vs')
      (Contravariant, NegRep) -> pure (ContravariantType tyPos : vartypes, (tyPos, tyNeg) : vs')

   paramsMap :: [(Variance, SkolemTVar, MonoKind)]-> [(Typ Pos, Typ Neg)] -> Bisubstitution
   paramsMap kindArgs freshVars =
     MkBisubstitution (M.fromList (zip ((\(_,tv,_) -> skolemTVarToTVar tv) <$> kindArgs) freshVars))

---------------------------------------------------------------------------------------------
-- Running computations in an extended context or environment
---------------------------------------------------------------------------------------------

withContext :: LinearContext 'Pos -> GenM a -> GenM a
withContext ctx = local (\(env,gr@GenerateReader{..}) -> (env, gr { context = ctx:context }))

---------------------------------------------------------------------------------------------
-- Looking up types in the context and environment
---------------------------------------------------------------------------------------------

-- | Lookup a type of a bound variable in the context.
lookupContext :: PrdCnsRep pc -> Index -> GenM (Typ (PrdCnsToPol pc))
lookupContext rep (i,j) = do
  ctx <- asks (context . snd)
  case indexMaybe ctx i of
    Nothing -> throwGenError ["Bound Variable out of bounds: ", "PrdCns: " <> T.pack (show rep),  "Index: " <> T.pack (show (i,j))]
    Just lctxt -> case indexMaybe lctxt j of
      Nothing -> throwGenError ["Bound Variable out of bounds: ", "PrdCns: " <> T.pack (show rep),  "Index: " <> T.pack (show (i,j))]
      Just ty -> case (rep, ty) of
        (PrdRep, PrdCnsType PrdRep ty) -> return ty
        (CnsRep, PrdCnsType CnsRep ty) -> return ty
        (PrdRep, PrdCnsType CnsRep _) -> throwGenError ["Bound Variable " <> T.pack (show (i,j)) <> " was expected to be PrdType, but CnsType was found."]
        (CnsRep, PrdCnsType PrdRep _) -> throwGenError ["Bound Variable " <> T.pack (show (i,j)) <> " was expected to be CnsType, but PrdType was found."]


---------------------------------------------------------------------------------------------
-- Instantiating type schemes with fresh unification variables.
---------------------------------------------------------------------------------------------

instantiateTypeScheme :: FreeVarName -> Loc -> TypeScheme pol -> GenM (Typ pol)
instantiateTypeScheme fv loc TypeScheme { ts_vars, ts_monotype } = do
  freshVars <- forM ts_vars (\tv -> freshTVar (TypeSchemeInstance fv loc) >>= \ty -> return (tv, ty))
  pure $ zonk (MkBisubstitution (M.fromList freshVars)) ts_monotype

---------------------------------------------------------------------------------------------
-- Adding a constraint
---------------------------------------------------------------------------------------------

-- | Add a constraint to the state.
addConstraint :: Constraint ConstraintInfo -> GenM ()
addConstraint c = modify foo
  where
    foo gs@GenerateState { constraintSet } = gs { constraintSet = bar constraintSet }
    bar cs@ConstraintSet { cs_constraints } = cs { cs_constraints = c:cs_constraints }

---------------------------------------------------------------------------------------------
-- Translate nominal types to structural refinement types
---------------------------------------------------------------------------------------------

-- | Recursively translate types in xtor signature to upper bound refinement types
translateXtorSigUpper :: XtorSig Neg -> GenM (XtorSig Neg)
translateXtorSigUpper xts = do
  env <- asks fst
  case TT.translateXtorSigUpper env xts of
    Left err -> throwError err
    Right xts' -> return xts'

-- | Recursively translate a nominal type to an upper bound refinement type
translateTypeUpper :: Typ Neg -> GenM (Typ Neg)
translateTypeUpper ty = do
  env <- asks fst
  case TT.translateTypeUpper env ty of
    Left err -> throwError err
    Right xts' -> return xts'

-- | Recursively translate types in xtor signature to lower bound refinement types
translateXtorSigLower :: XtorSig Pos -> GenM (XtorSig Pos)
translateXtorSigLower xts = do
  env <- asks fst
  case TT.translateXtorSigLower env xts of
    Left err -> throwError err
    Right xts' -> return xts'

-- | Recursively translate a nominal type to a lower bound refinement type
translateTypeLower :: Typ Pos -> GenM (Typ Pos)
translateTypeLower ty = do
  env <- asks fst
  case TT.translateTypeLower env ty of
    Left err -> throwError err
    Right xts' -> return xts'

---------------------------------------------------------------------------------------------
-- Other
---------------------------------------------------------------------------------------------

-- | Specifies whether to infer nominal or refined types
data InferenceMode = InferNominal | InferRefined
  deriving (Eq, Show)

foo :: PrdCnsRep pc -> PolarityRep (PrdCnsToPol pc)
foo PrdRep = PosRep
foo CnsRep = NegRep

fromMaybeVar :: Maybe FreeVarName -> FreeVarName
fromMaybeVar Nothing = MkFreeVarName "generated"
fromMaybeVar (Just fv) = fv

-- | Checks for a given list of XtorNames and a type declaration whether all the xtor names occur in
-- the type declaration (Correctness).
checkCorrectness :: [XtorName]
                 -> DataDecl
                 -> GenM ()
checkCorrectness matched decl = do
  let declared = sig_name <$> fst (data_xtors decl)
  forM_ matched $ \xn -> unless (xn `elem` declared)
    (throwGenError ["Pattern Match Error. The xtor " <> ppPrint xn <> " does not occur in the declaration of type " <> ppPrint (data_name decl)])

-- | Checks for a given list of XtorNames and a type declaration whether all xtors of the type declaration
-- are matched against (Exhaustiveness).
checkExhaustiveness :: [XtorName] -- ^ The xtor names used in the pattern match
                    -> DataDecl   -- ^ The type declaration to check against.
                    -> GenM ()
checkExhaustiveness matched decl = do
  let declared = sig_name <$> fst (data_xtors decl)
  forM_ declared $ \xn -> unless (xn `elem` matched)
    (throwGenError ["Pattern Match Exhaustiveness Error. Xtor: " <> ppPrint xn <> " of type " <>
                     ppPrint (data_name decl) <> " is not matched against." ])

-- | Check well-definedness of an instance, i.e. every method specified in the class declaration is implemented
-- in the instance declaration and every implemented method is actually declared.
checkInstanceCoverage :: RST.ClassDeclaration -- ^ The class declaration to check against.
                      -> [MethodName]         -- ^ The methods implemented in the instance.
                      -> GenM ()
checkInstanceCoverage RST.MkClassDeclaration { classdecl_xtors } instanceMethods = do
  let classMethods = MkMethodName . unXtorName . fst <$> classdecl_xtors
  forM_ classMethods $ \m -> unless (m `elem` instanceMethods)
    (throwGenError ["Instance Declaration Error. Method: " <> ppPrint m <> " is declared but not implemented." ])
  forM_ instanceMethods $ \m -> unless (m `elem` classMethods)
    (throwGenError ["Instance Declaration Error. Method: " <> ppPrint m <> " is implemented but not declared." ])