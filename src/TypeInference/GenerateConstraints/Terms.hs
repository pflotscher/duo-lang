module TypeInference.GenerateConstraints.Terms
  ( genConstraintsTerm
  , genConstraintsTermRecursive
  , genConstraintsCommand
  ) where

import Control.Monad.Reader
import Data.List (find)
import Pretty.Terms ()
import Pretty.Types ()
import Syntax.Terms
import Syntax.CommonTerm
import Syntax.Types
import TypeInference.GenerateConstraints.Definition
import TypeInference.Constraints
import Utils
import Lookup

---------------------------------------------------------------------------------------------
-- Terms
---------------------------------------------------------------------------------------------

genConstraintsPCTerm :: PrdCnsTerm Parsed
                    -> GenM (PrdCnsTerm Inferred)
genConstraintsPCTerm (PrdTerm tm) = PrdTerm <$> genConstraintsTerm tm
genConstraintsPCTerm (CnsTerm tm) = CnsTerm <$> genConstraintsTerm tm

genConstraintsArgs :: Substitution Parsed
                   -> GenM (Substitution Inferred)
genConstraintsArgs subst = sequence (genConstraintsPCTerm <$> subst)

genConstraintsCtxts :: LinearContext Pos -> LinearContext Neg -> ConstraintInfo -> GenM ()
genConstraintsCtxts [] [] _ = return ()
genConstraintsCtxts ((PrdType ty1) : rest1) (PrdType ty2 : rest2) info = do
  addConstraint $ SubType info ty1 ty2
  genConstraintsCtxts rest1 rest2 info
genConstraintsCtxts ((CnsType ty1) : rest1) (CnsType ty2 : rest2) info = do
  addConstraint $ SubType info ty2 ty1
  genConstraintsCtxts rest1 rest2 info
genConstraintsCtxts _ _ _ = throwGenError ["Boom"]

-- | Generate the constraints for a given Term.
genConstraintsTerm :: Term pc Parsed
                    -> GenM (Term pc Inferred)
--
-- Bound variables:
--
-- Bound variables can be looked up in the context.
--
genConstraintsTerm (BoundVar loc PrdRep idx) = do
  ty <- lookupContext PrdRep idx
  return (BoundVar (loc, ty) PrdRep idx)
genConstraintsTerm (BoundVar loc CnsRep idx) = do
  ty <- lookupContext CnsRep idx
  return (BoundVar (loc, ty) CnsRep idx)
--
-- Free variables:
--
-- Free variables can be looked up in the environment,
-- where they correspond to typing schemes. This typing
-- scheme has to be instantiated with fresh unification variables.
--
genConstraintsTerm (FreeVar loc PrdRep v) = do
  tys <- snd <$> lookupSTerm PrdRep v
  ty <- instantiateTypeScheme v loc tys
  return (FreeVar (loc, ty) PrdRep v)
genConstraintsTerm (FreeVar loc CnsRep v) = do
  tys <- snd <$> lookupSTerm CnsRep v
  ty <- instantiateTypeScheme v loc tys
  return (FreeVar (loc, ty) CnsRep v)
--
-- Xtors
--
genConstraintsTerm (XtorCall loc rep xt args) = do
  args' <- genConstraintsArgs args
  let argTypes = getTypArgs args'
  case xtorNominalStructural xt of
    Structural -> do
      case rep of
        PrdRep -> return $ XtorCall (loc, TyData   PosRep Nothing [MkXtorSig xt (getTypArgs args')]) rep xt args'
        CnsRep -> return $ XtorCall (loc, TyCodata NegRep Nothing [MkXtorSig xt (getTypArgs args')]) rep xt args'
    Nominal -> do
      tn <- lookupDataDecl xt
      im <- asks (inferMode . snd)
      -- Check if args of xtor are correct
      xtorSig <- case im of
        InferNominal -> lookupXtorSig xt NegRep
        InferRefined -> translateXtorSigUpper =<< lookupXtorSig xt NegRep
      genConstraintsCtxts argTypes (sig_args xtorSig) (case rep of { PrdRep -> CtorArgsConstraint loc; CnsRep -> DtorArgsConstraint loc })
      case (im, rep) of
            (InferNominal,PrdRep) -> return (XtorCall (loc, TyNominal PosRep (data_name tn))                               rep xt args')
            (InferRefined,PrdRep) -> return (XtorCall (loc, TyData PosRep (Just $ data_name tn) [MkXtorSig xt argTypes])   rep xt args')
            (InferNominal,CnsRep) -> return (XtorCall (loc, TyNominal NegRep (data_name tn))                               rep xt args')
            (InferRefined,CnsRep) -> return (XtorCall (loc, TyCodata NegRep (Just $ data_name tn) [MkXtorSig xt argTypes]) rep xt args')

--
-- Structural pattern and copattern matches:
--
genConstraintsTerm (XMatch loc rep Structural cases) = do
  cases' <- forM cases (\MkSCase{..} -> do
                      (fvarsPos, fvarsNeg) <- freshTVars ((\(pc,tv) -> (pc,fromMaybeVar tv)) <$> scase_args)
                      cmd' <- withContext fvarsPos (genConstraintsCommand scase_cmd)
                      return (MkSCase scase_ext scase_name scase_args cmd', MkXtorSig scase_name fvarsNeg))
  case rep of
        PrdRep -> return $ XMatch (loc, TyCodata PosRep Nothing (snd <$> cases')) rep Structural (fst <$> cases')
        CnsRep -> return $ XMatch (loc, TyData   NegRep Nothing (snd <$> cases')) rep Structural (fst <$> cases')

--
-- Nominal pattern and copattern matches:
--
genConstraintsTerm (XMatch _ _ Nominal []) =
  -- We know that empty matches cannot be parsed as nominal.
  -- It is therefore save to take the head of the xtors in the other cases.
  throwGenError ["Unreachable: A nominal match needs to have at least one case."]
genConstraintsTerm (XMatch loc rep Nominal cases@(pmcase:_)) = do
  tn <- lookupDataDecl (scase_name pmcase)
  checkCorrectness (scase_name <$> cases) tn
  checkExhaustiveness (scase_name <$> cases) tn
  im <- asks (inferMode . snd)
  cases' <- forM cases (\MkSCase {..} -> do
                           (fvarsPos, fvarsNeg) <- freshTVars ((\(pc,tv) -> (pc,fromMaybeVar tv)) <$> scase_args)
                           cmd' <- withContext fvarsPos (genConstraintsCommand scase_cmd)
                           case im of
                             InferNominal -> do
                               x <- sig_args <$> lookupXtorSig scase_name PosRep
                               genConstraintsCtxts x fvarsNeg (PatternMatchConstraint loc)
                             InferRefined -> do
                               x1 <- sig_args <$> (translateXtorSigLower =<< lookupXtorSig scase_name PosRep)
                               x2 <- sig_args <$> (translateXtorSigUpper =<< lookupXtorSig scase_name NegRep)
                               genConstraintsCtxts x1 fvarsNeg (PatternMatchConstraint loc) -- Empty translation as lower bound
                               genConstraintsCtxts fvarsPos x2 (PatternMatchConstraint loc) -- Full translation as upper bound
                           return (MkSCase scase_ext scase_name scase_args cmd', MkXtorSig scase_name fvarsNeg))
  case (im, rep) of
        (InferNominal,PrdRep) -> return $ XMatch (loc, TyNominal PosRep (data_name tn))                        rep Nominal (fst <$> cases')
        (InferRefined,PrdRep) -> return $ XMatch (loc, TyCodata PosRep (Just $ data_name tn) (snd <$> cases')) rep Nominal (fst <$> cases')
        (InferNominal,CnsRep) -> return $ XMatch (loc, TyNominal NegRep (data_name tn))                        rep Nominal (fst <$> cases')
        (InferRefined,CnsRep) -> return $ XMatch (loc, TyData NegRep (Just $ data_name tn) (snd <$> cases'))   rep Nominal (fst <$> cases')
--
-- Mu and TildeMu abstractions:
--
genConstraintsTerm (MuAbs loc PrdRep bs cmd) = do
  (fvpos, fvneg) <- freshTVar (ProgramVariable (fromMaybeVar bs))
  cmd' <- withContext [CnsType fvneg] (genConstraintsCommand cmd)
  return (MuAbs (loc, fvpos) PrdRep bs cmd')
genConstraintsTerm (MuAbs loc CnsRep bs cmd) = do
  (fvpos, fvneg) <- freshTVar (ProgramVariable (fromMaybeVar bs))
  cmd' <- withContext [PrdType fvpos] (genConstraintsCommand cmd)
  return (MuAbs (loc, fvneg) CnsRep bs cmd')
--
-- Dtor Sugar
--
genConstraintsTerm (Dtor loc xt@MkXtorName { xtorNominalStructural = Structural } t args) = do
  args' <- sequence (genConstraintsTerm <$> args)
  (retTypePos, retTypeNeg) <- freshTVar (DtorAp loc)
  let codataType = TyCodata NegRep Nothing [MkXtorSig xt ((PrdType . getTypeTerm <$> args') ++  [CnsType retTypeNeg])]
  t' <- genConstraintsTerm t
  addConstraint (SubType (DtorApConstraint loc) (getTypeTerm t') codataType)
  return (Dtor (loc,retTypePos) xt t' args')
genConstraintsTerm (Dtor loc xt@MkXtorName { xtorNominalStructural = Nominal } t args) = do
  args' <- sequence (genConstraintsTerm <$> args)
  tn <- lookupDataDecl xt
  t'<- genConstraintsTerm t
  im <- asks (inferMode . snd)
  ty <- case im of
    InferNominal -> return $ TyNominal NegRep (data_name tn)
    InferRefined -> translateTypeUpper $ TyNominal NegRep (data_name tn)
  addConstraint (SubType (DtorApConstraint loc) (getTypeTerm t') ty )
  im <- asks (inferMode . snd)
  xtorSig <- case im of
    InferNominal -> lookupXtorSig xt NegRep
    InferRefined -> translateXtorSigUpper =<< lookupXtorSig xt NegRep
  when (length args' /= length (sig_args xtorSig)  - 1) $
    throwGenError ["Dtor " <> unXtorName xt <> " called with incorrect number of arguments"]
  -- Nominal type constraint!!
  genConstraintsCtxts (PrdType . getTypeTerm <$> args') (sig_args xtorSig) (DtorArgsConstraint loc)
  --forM_ (zip args' (prdTypes $ sig_args xtorSig)) $ \(t1,t2) -> addConstraint $ SubType (DtorArgsConstraint loc) (getTypeSTerm t1) t2
  let retType =case reverse (sig_args xtorSig) of
        [] -> error "BANG"
        (CnsType ty) : _ -> ty
        (PrdType _) : _ -> error "BANG"
  return (Dtor (loc,retType) xt t' args')

{-
match t with { X_1(x_1,...,x_n) => e_1, ... }

If X_1 has nominal type N, then:
- T <: N for t:T
- All X_i must be constructors of type N (correctness)
- All constructors of type N must appear in match (exhaustiveness)
- All e_i must have same type, this is the return type
- Types of x_1,...,x_n in e_i must correspond with types in declaration of X_i
-}
genConstraintsTerm (Match loc t cases@(MkACase _ xtn@(MkXtorName Nominal _) _ _:_)) = do
  t' <- genConstraintsTerm t
  tn@NominalDecl{..} <- lookupDataDecl xtn
  checkCorrectness (acase_name <$> cases) tn
  checkExhaustiveness (acase_name <$> cases) tn
  (retTypePos, retTypeNeg) <- freshTVar (PatternMatch loc)
  (cases',casesXtssNeg,casesXtssPos) <- unzip3 <$> sequence (genConstraintsATermCase retTypeNeg <$> cases)
  im <- asks (inferMode . snd)
  -- Nominal type constraint!!
  case im of
    InferNominal -> genConstraintsACaseArgs (data_xtors PosRep) casesXtssNeg loc
    InferRefined -> do
      xtssLower <- mapM translateXtorSigLower $ data_xtors PosRep 
      xtssUpper <- mapM translateXtorSigUpper $ data_xtors NegRep
      genConstraintsACaseArgs xtssLower casesXtssNeg loc -- empty refinement as lower bound
      genConstraintsACaseArgs casesXtssPos xtssUpper loc -- full refinement as upper bound
  let ty = case im of
        InferNominal -> TyNominal NegRep data_name
        InferRefined -> TyData NegRep (Just data_name) casesXtssNeg
  addConstraint (SubType (PatternMatchConstraint loc) (getTypeTerm t') ty)
  return (Match (loc,retTypePos) t' cases')

genConstraintsTerm (Match loc t cases) = do
  t' <- genConstraintsTerm t
  (retTypePos, retTypeNeg) <- freshTVar (PatternMatch loc)
  (cases',casesXtssNeg,_) <- unzip3 <$> sequence (genConstraintsATermCase retTypeNeg <$> cases)
  addConstraint (SubType (PatternMatchConstraint loc) (getTypeTerm t') (TyData NegRep Nothing casesXtssNeg))
  return (Match (loc, retTypePos) t' cases')

{-
comatch { X_1(x_1,...,x_n) => e_1, ... }

If X_1 has nominal type N, then:
- All X_i must be destructors of type N (correctness)
- All destructors of type N must appear in comatch (exhaustiveness)
- All e_i must have same type, this is the return type
- Types of x_1,...,x_n in e_i must correspond with types in declaration of X_i
-}
genConstraintsTerm (Comatch loc cocases@(MkACase _ xtn@(MkXtorName Nominal _) _ _:_)) = do
  tn@NominalDecl{..} <- lookupDataDecl xtn
  checkCorrectness (acase_name <$> cocases) tn
  checkExhaustiveness (acase_name <$> cocases) tn
  (cocases',cocasesXtssNeg,cocasesXtssPos) <- unzip3 <$> sequence (genConstraintsATermCocase <$> cocases)
  im <- asks (inferMode . snd)
  -- Nominal type constraint!!
  case im of
    InferNominal -> genConstraintsACaseArgs (data_xtors PosRep) cocasesXtssNeg loc
    InferRefined -> do
      xtssLower <- mapM translateXtorSigLower $ data_xtors PosRep
      xtssUpper <- mapM translateXtorSigUpper $ data_xtors NegRep
      genConstraintsACaseArgs xtssLower cocasesXtssNeg loc -- empty refinement as lower bound
      genConstraintsACaseArgs cocasesXtssPos xtssUpper loc -- full refinement as upper bound
  let ty = case im of
        InferNominal -> TyNominal PosRep data_name
        InferRefined -> TyCodata PosRep (Just data_name) cocasesXtssNeg
  return (Comatch (loc, ty) cocases')

genConstraintsTerm (Comatch loc cocases) = do
  (cocases',cocasesXtssNeg,_) <- unzip3 <$> sequence (genConstraintsATermCocase <$> cocases)
  let ty = TyCodata PosRep Nothing cocasesXtssNeg
  return (Comatch (loc,ty) cocases')

genConstraintsATermCase :: Typ Neg
                        -> ACase Parsed
                        -> GenM (ACase Inferred, XtorSig Neg, XtorSig Pos)
genConstraintsATermCase retType MkACase { acase_ext, acase_name, acase_args, acase_term } = do
  (argtsPos,argtsNeg) <- unzip <$> forM acase_args (freshTVar . ProgramVariable . fromMaybeVar) -- Generate type var for each case arg
  acase_term' <- withContext (PrdType <$> argtsPos) (genConstraintsTerm acase_term) -- Type case term using new type vars
  addConstraint (SubType (CaseConstraint acase_ext) (getTypeTerm acase_term') retType) -- Case type
  let sigNeg = MkXtorSig acase_name (PrdType <$>  argtsNeg)
  let sigPos = MkXtorSig acase_name (PrdType <$> argtsPos)
  return (MkACase acase_ext acase_name acase_args acase_term', sigNeg, sigPos)

genConstraintsATermCocase :: ACase Parsed
                          -> GenM (ACase Inferred, XtorSig Neg, XtorSig Pos)
genConstraintsATermCocase MkACase { acase_ext, acase_name, acase_args, acase_term } = do
  (argtsPos,argtsNeg) <- unzip <$> forM acase_args (freshTVar . ProgramVariable . fromMaybeVar)
  acase_term'<- withContext (PrdType <$> argtsPos) (genConstraintsTerm acase_term)
  let sigNeg = MkXtorSig acase_name ((PrdType <$> argtsNeg) ++ [CnsType $ getTypeTerm acase_term'])
  let sigPos = MkXtorSig acase_name (PrdType <$> argtsPos)
  return (MkACase acase_ext acase_name acase_args acase_term', sigNeg, sigPos)

genConstraintsACaseArgs :: [XtorSig Pos] -> [XtorSig Neg] -> Loc -> GenM ()
genConstraintsACaseArgs xtsigs1 xtsigs2 loc = do
  forM_ xtsigs1 (\xts1@(MkXtorSig xtn1 _) -> do
    case find (\case (MkXtorSig xtn2 _) -> xtn1==xtn2) xtsigs2 of
      Just xts2 -> do
        let sa1 = sig_args xts1; sa2 = sig_args xts2
        genConstraintsCtxts sa1 sa2 (PatternMatchConstraint loc)
      Nothing -> return ()
    )


genConstraintsCommand :: Command Parsed -> GenM (Command Inferred)
genConstraintsCommand (Done loc) = return (Done loc)
genConstraintsCommand (Print loc t) = do
  t' <- genConstraintsTerm t
  return (Print loc t')
genConstraintsCommand (Apply loc t1 t2) = do
  t1' <- genConstraintsTerm t1
  t2' <- genConstraintsTerm t2
  addConstraint (SubType (CommandConstraint loc) (getTypeTerm t1') (getTypeTerm t2'))
  return (Apply loc t1' t2')

---------------------------------------------------------------------------------------------
-- Symmetric Terms with recursive binding
---------------------------------------------------------------------------------------------

genConstraintsTermRecursive :: Loc
                             -> FreeVarName
                             -> PrdCnsRep pc -> Term pc Parsed
                             -> GenM (Term pc Inferred)
genConstraintsTermRecursive loc fv PrdRep tm = do
  (x,y) <- freshTVar (RecursiveUVar fv)
  tm <- withSTerm PrdRep fv (FreeVar (loc, x) PrdRep fv) loc (TypeScheme [] x) (genConstraintsTerm tm)
  addConstraint (SubType RecursionConstraint (getTypeTerm tm) y)
  return tm
genConstraintsTermRecursive loc fv CnsRep tm = do
  (x,y) <- freshTVar (RecursiveUVar fv)
  tm <- withSTerm CnsRep fv (FreeVar (loc,y) CnsRep fv) loc (TypeScheme [] y) (genConstraintsTerm tm)
  addConstraint (SubType RecursionConstraint x (getTypeTerm tm))
  return tm

