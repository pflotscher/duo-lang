module TypeInference.GenerateConstraints.ATerms
  ( genConstraintsATerm
  ) where

import Control.Monad.Reader
import Data.List (find)

import Syntax.CommonTerm
import Syntax.Terms
import Syntax.Types
import TypeInference.GenerateConstraints.Definition
import TypeInference.Constraints
import Utils
import Lookup

---------------------------------------------------------------------------------------------
-- Asymmetric Terms
---------------------------------------------------------------------------------------------

-- | Every asymmetric terms gets assigned a positive type.
genConstraintsATerm :: STerm pc Parsed
                    -> GenM (STerm pc Inferred)
genConstraintsATerm (Dtor loc xt@MkXtorName { xtorNominalStructural = Structural } t args) = do
  args' <- sequence (genConstraintsATerm <$> args)
  (retTypePos, retTypeNeg) <- freshTVar (DtorAp loc)
  let codataType = TyCodata NegRep Nothing [MkXtorSig xt (MkTypArgs (getTypeSTerm <$> args') [retTypeNeg])]
  t' <- genConstraintsATerm t
  addConstraint (SubType (DtorApConstraint loc) (getTypeSTerm t') codataType)
  return (Dtor (loc,retTypePos) xt t' args')
genConstraintsATerm (Dtor loc xt@MkXtorName { xtorNominalStructural = Nominal } t args) = do
  args' <- sequence (genConstraintsATerm <$> args)
  tn <- lookupDataDecl xt
  t'<- genConstraintsATerm t
  im <- asks (inferMode . snd)
  ty <- case im of
    InferNominal -> return $ TyNominal NegRep (data_name tn)
    InferRefined -> translateTypeUpper $ TyNominal NegRep (data_name tn)
  addConstraint (SubType (DtorApConstraint loc) (getTypeSTerm t') ty )
  im <- asks (inferMode . snd)
  xtorSig <- case im of
    InferNominal -> lookupXtorSig xt NegRep
    InferRefined -> translateXtorSigUpper =<< lookupXtorSig xt NegRep
  when (length args' /= length (prdTypes $ sig_args xtorSig)) $
    throwGenError ["Dtor " <> unXtorName xt <> " called with incorrect number of arguments"]
  -- Nominal type constraint!!
  forM_ (zip args' (prdTypes $ sig_args xtorSig)) $ \(t1,t2) -> addConstraint $ SubType (DtorArgsConstraint loc) (getTypeSTerm t1) t2
  let retType = head $ cnsTypes $ sig_args xtorSig
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
genConstraintsATerm (Match loc t cases@(MkACase _ xtn@(MkXtorName Nominal _) _ _:_)) = do
  t' <- genConstraintsATerm t
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
  addConstraint (SubType (PatternMatchConstraint loc) (getTypeSTerm t') ty)
  return (Match (loc,retTypePos) t' cases')

genConstraintsATerm (Match loc t cases) = do
  t' <- genConstraintsATerm t
  (retTypePos, retTypeNeg) <- freshTVar (PatternMatch loc)
  (cases',casesXtssNeg,_) <- unzip3 <$> sequence (genConstraintsATermCase retTypeNeg <$> cases)
  addConstraint (SubType (PatternMatchConstraint loc) (getTypeSTerm t') (TyData NegRep Nothing casesXtssNeg))
  return (Match (loc, retTypePos) t' cases')

{-
comatch { X_1(x_1,...,x_n) => e_1, ... }

If X_1 has nominal type N, then:
- All X_i must be destructors of type N (correctness)
- All destructors of type N must appear in comatch (exhaustiveness)
- All e_i must have same type, this is the return type
- Types of x_1,...,x_n in e_i must correspond with types in declaration of X_i
-}
genConstraintsATerm (Comatch loc cocases@(MkACase _ xtn@(MkXtorName Nominal _) _ _:_)) = do
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

genConstraintsATerm (Comatch loc cocases) = do
  (cocases',cocasesXtssNeg,_) <- unzip3 <$> sequence (genConstraintsATermCocase <$> cocases)
  let ty = TyCodata PosRep Nothing cocasesXtssNeg
  return (Comatch (loc,ty) cocases')

genConstraintsATermCase :: Typ Neg
                        -> ACase Parsed
                        -> GenM (ACase Inferred, XtorSig Neg, XtorSig Pos)
genConstraintsATermCase retType MkACase { acase_ext, acase_name, acase_args, acase_term } = do
  (argtsPos,argtsNeg) <- unzip <$> forM acase_args (freshTVar . ProgramVariable . fromMaybeVar) -- Generate type var for each case arg
  acase_term' <- withContext (MkTypArgs argtsPos []) (genConstraintsATerm acase_term) -- Type case term using new type vars
  addConstraint (SubType (CaseConstraint acase_ext) (getTypeSTerm acase_term') retType) -- Case type
  let sigNeg = MkXtorSig acase_name (MkTypArgs argtsNeg [])
  let sigPos = MkXtorSig acase_name (MkTypArgs argtsPos [])
  return (MkACase acase_ext acase_name acase_args acase_term', sigNeg, sigPos)

genConstraintsATermCocase :: ACase Parsed
                          -> GenM (ACase Inferred, XtorSig Neg, XtorSig Pos)
genConstraintsATermCocase MkACase { acase_ext, acase_name, acase_args, acase_term } = do
  (argtsPos,argtsNeg) <- unzip <$> forM acase_args (freshTVar . ProgramVariable . fromMaybeVar)
  acase_term'<- withContext (MkTypArgs argtsPos []) (genConstraintsATerm acase_term)
  let sigNeg = MkXtorSig acase_name (MkTypArgs argtsNeg [getTypeSTerm acase_term'])
  let sigPos = MkXtorSig acase_name (MkTypArgs argtsPos [])
  return (MkACase acase_ext acase_name acase_args acase_term', sigNeg, sigPos)

genConstraintsACaseArgs :: [XtorSig Pos] -> [XtorSig Neg] -> Loc -> GenM ()
genConstraintsACaseArgs xtsigs1 xtsigs2 loc = do
  forM_ xtsigs1 (\xts1@(MkXtorSig xtn1 _) -> do
    case find (\case (MkXtorSig xtn2 _) -> xtn1==xtn2) xtsigs2 of
      Just xts2 -> do
        let sa1 = sig_args xts1; sa2 = sig_args xts2
        zipWithM_ (\pt1 pt2 -> addConstraint $ SubType (PatternMatchConstraint loc) pt1 pt2) (prdTypes sa1) (prdTypes sa2)
        zipWithM_ (\ct1 ct2 -> addConstraint $ SubType (PatternMatchConstraint loc) ct2 ct1) (cnsTypes sa1) (cnsTypes sa2)
      Nothing -> return ()
    )


