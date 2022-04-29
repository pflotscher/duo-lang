module TypeInference.GenerateConstraints.Terms
  ( genConstraintsTerm
  , genConstraintsTermRecursive
  , genConstraintsCommand
  ) where

import Control.Monad.Reader
import Data.Map qualified as M
import Data.Text qualified as T
import Pretty.Terms ()
import Pretty.Types ()
import Pretty.Constraints ()
import Pretty.Pretty ( ppPrint )
import Syntax.AST.Terms qualified as AST
import Syntax.RST.Terms qualified as RST
import Syntax.Common hiding (primOps)
import Syntax.RST.Types
import TypeInference.GenerateConstraints.Definition
import TypeInference.Constraints
import Utils
import Lookup
import TypeInference.GenerateConstraints.Primitives (primOps)

---------------------------------------------------------------------------------------------
-- Substitutions and Linear Contexts
---------------------------------------------------------------------------------------------

genConstraintsPCTerm :: RST.PrdCnsTerm
                     -> GenM AST.PrdCnsTerm
genConstraintsPCTerm (RST.PrdTerm tm) = AST.PrdTerm <$> genConstraintsTerm tm
genConstraintsPCTerm (RST.CnsTerm tm) = AST.CnsTerm <$> genConstraintsTerm tm

genConstraintsSubst :: RST.Substitution
                    -> GenM AST.Substitution
genConstraintsSubst subst = sequence (genConstraintsPCTerm <$> subst)

genConstraintsCtxts :: LinearContext Pos -> LinearContext Neg -> ConstraintInfo -> GenM ()
genConstraintsCtxts ctx1 ctx2 info | length ctx1 /= length ctx2 = throwGenError ["genConstraintsCtxts: Linear contexts have unequal length"
                                                                                , "Constraint Info: " <> ppPrint info
                                                                                , "Pos context: " <> ppPrint ctx1
                                                                                , "Neg context: " <> ppPrint ctx2]
genConstraintsCtxts [] [] _ = return ()
genConstraintsCtxts ((PrdCnsType PrdRep ty1) : rest1) (PrdCnsType PrdRep ty2 : rest2) info = do
  addConstraint $ SubType info ty1 ty2
  genConstraintsCtxts rest1 rest2 info
genConstraintsCtxts ((PrdCnsType CnsRep ty1) : rest1) (PrdCnsType CnsRep ty2 : rest2) info = do
  addConstraint $ SubType info ty2 ty1
  genConstraintsCtxts rest1 rest2 info
genConstraintsCtxts (PrdCnsType PrdRep _:_) (PrdCnsType CnsRep _:_) info =
  throwGenError ["genConstraintsCtxts: Tried to constrain PrdType by CnsType", "Constraint Info: " <> ppPrint info]
genConstraintsCtxts (PrdCnsType CnsRep _:_) (PrdCnsType PrdRep _:_) info =
  throwGenError ["genConstraintsCtxts: Tried to constrain CnsType by PrdType", "ConstraintInfo: " <> ppPrint info]
genConstraintsCtxts [] (_:_) info =
  throwGenError ["genConstraintsCtxts: Linear contexts have unequal length.", "Constraint Info: " <> ppPrint info]
genConstraintsCtxts (_:_) [] info =
  throwGenError ["genConstraintsCtxts: Linear contexts have unequal length.", "Constraint Info: " <> ppPrint info]


splitContext :: Int -- ^ The offset of the projected type
             -> PrdCnsRep pc -- ^ The expected mode of the type
             -> LinearContext pol -- ^ The context to be split
             -> GenM (LinearContext pol, Typ (PrdCnsFlip pc pol), LinearContext pol)
splitContext n PrdRep sig = case splitAt n sig of
                              (_, []) -> throwGenError ["splitContext: Too short."]
                              (_, PrdCnsType CnsRep _:_) -> throwGenError ["splitContext: Found CnsType, expected PrdType."]
                              (tys1, PrdCnsType PrdRep ty:tys2) -> pure (tys1, ty, tys2)
splitContext n CnsRep sig = case splitAt n sig of
                              (_, []) -> throwGenError ["splitContext: Too short."]
                              (_, PrdCnsType PrdRep _:_) -> throwGenError ["splitContext: Found PrdType, expected CnsType."]
                              (tys1, PrdCnsType CnsRep ty:tys2) -> pure (tys1, ty, tys2)

---------------------------------------------------------------------------------------------
-- Terms
---------------------------------------------------------------------------------------------

-- | Generate the constraints for a given Term.
genConstraintsTerm :: RST.Term pc
                    -> GenM (AST.Term pc)
--
-- Bound variables:
--
-- Bound variables can be looked up in the context.
--
genConstraintsTerm (RST.BoundVar loc rep idx) = do
  ty <- lookupContext rep idx
  return (AST.BoundVar loc rep ty idx)
--
-- Free variables:
--
-- Free variables can be looked up in the environment,
-- where they correspond to typing schemes. This typing
-- scheme has to be instantiated with fresh unification variables.
--
genConstraintsTerm (RST.FreeVar loc rep v) = do
  tys <- snd <$> lookupTerm rep v
  ty <- instantiateTypeScheme v loc tys
  return (AST.FreeVar loc rep ty v)
--
-- Structural Xtors:
--
genConstraintsTerm (RST.Xtor loc rep Structural xt subst) = do
  inferredSubst <- genConstraintsSubst subst
  let substTypes = AST.getTypArgs inferredSubst
  case rep of
    PrdRep -> return $ AST.Xtor loc rep (TyData   defaultLoc PosRep Nothing [MkXtorSig xt substTypes]) Structural xt inferredSubst
    CnsRep -> return $ AST.Xtor loc rep (TyCodata defaultLoc NegRep Nothing [MkXtorSig xt substTypes]) Structural xt inferredSubst
--
-- Nominal Xtors
--
genConstraintsTerm (RST.Xtor loc rep Nominal xt subst) = do
  -- First we infer the types of the arguments.
  substInferred <- genConstraintsSubst subst
  let substTypes = AST.getTypArgs substInferred
  -- Secondly we look up the argument types of the xtor in the type declaration.
  decl <- lookupDataDecl xt
  xtorSig <- lookupXtorSig xt NegRep
  -- Generate fresh unification variables for type parameters
  (args, tyParamsMap) <- freshTVarsForTypeParams (prdCnsToPol rep) decl
  -- Substitute these for the type parameters in the constructor signature
  let sig_args' = zonk tyParamsMap (sig_args xtorSig)
  -- Then we generate constraints between the inferred types of the substitution
  -- and the types we looked up, i.e. the types declared in the XtorSig.
  genConstraintsCtxts substTypes sig_args' (case rep of { PrdRep -> CtorArgsConstraint loc; CnsRep -> DtorArgsConstraint loc })
  case rep of
    PrdRep -> return (AST.Xtor loc rep (TyNominal defaultLoc PosRep Nothing (data_name decl) args) Nominal xt substInferred)
    CnsRep -> return (AST.Xtor loc rep (TyNominal defaultLoc NegRep Nothing (data_name decl) args) Nominal xt substInferred)
--
-- Refinement Xtors
--
genConstraintsTerm (RST.Xtor loc rep Refinement xt subst) = do
  -- First we infer the types of the arguments.
  substInferred <- genConstraintsSubst subst
  let substTypes = AST.getTypArgs substInferred
  -- Secondly we look up the argument types of the xtor in the type declaration.
  -- Since we infer refinement types, we have to look up the translated xtorSig.
  decl <- lookupDataDecl xt
  xtorSigUpper <- translateXtorSigUpper =<< lookupXtorSig xt NegRep
  -- Then we generate constraints between the inferred types of the substitution
  -- and the translations of the types we looked up, i.e. the types declared in the XtorSig.
  genConstraintsCtxts substTypes (sig_args xtorSigUpper) (case rep of { PrdRep -> CtorArgsConstraint loc; CnsRep -> DtorArgsConstraint loc })
  case rep of
    PrdRep -> return (AST.Xtor loc rep (TyData   defaultLoc PosRep (Just (data_name decl)) [MkXtorSig xt substTypes]) Refinement xt substInferred)
    CnsRep -> return (AST.Xtor loc rep (TyCodata defaultLoc NegRep (Just (data_name decl)) [MkXtorSig xt substTypes]) Refinement xt substInferred)
--
-- Structural pattern and copattern matches:
--
genConstraintsTerm (RST.XCase loc rep Structural cases) = do
  inferredCases <- forM cases (\RST.MkCmdCase{ cmdcase_pat = RST.XtorPat xt args, cmdcase_loc, cmdcase_cmd} -> do
                      -- Generate positive and negative unification variables for all variables
                      -- bound in the pattern.
                      (uvarsPos, uvarsNeg) <- freshTVars args
                      -- Check the command in the context extended with the positive unification variables
                      cmdInferred <- withContext uvarsPos (genConstraintsCommand cmdcase_cmd)
                      -- Return the negative unification variables in the returned type.
                      return (AST.MkCmdCase cmdcase_loc (AST.XtorPat xt args) cmdInferred, MkXtorSig xt uvarsNeg))
  case rep of
    -- The return type is a structural type consisting of a XtorSig for each case.
    PrdRep -> return $ AST.XCase loc rep (TyCodata defaultLoc PosRep Nothing (snd <$> inferredCases)) Structural (fst <$> inferredCases)
    CnsRep -> return $ AST.XCase loc rep (TyData   defaultLoc NegRep Nothing (snd <$> inferredCases)) Structural (fst <$> inferredCases)
--
-- Nominal pattern and copattern matches
--
genConstraintsTerm (RST.XCase _ _ Nominal []) =
  -- We know that empty matches cannot be parsed as nominal.
  -- It is therefore safe to pattern match on the head of the xtors in the other cases.
  throwGenError ["Unreachable: A nominal match needs to have at least one case."]
genConstraintsTerm (RST.XCase loc rep Nominal cases@(pmcase:_)) = do
  -- We lookup the data declaration based on the first pattern match case.
  decl <- lookupDataDecl (case (RST.cmdcase_pat pmcase) of (RST.XtorPat xt _) -> xt)
  -- We check that all cases in the pattern match belong to the type declaration.
  checkCorrectness ((\cs -> case RST.cmdcase_pat cs of RST.XtorPat xt _ -> xt) <$> cases) decl
  -- We check that all xtors in the type declaration are matched against.
  checkExhaustiveness ((\cs -> case RST.cmdcase_pat cs of RST.XtorPat xt _ -> xt) <$> cases) decl
  -- Generate fresh unification variables for type parameters
  (args, tyParamsMap) <- freshTVarsForTypeParams (prdCnsToPol rep) decl

  inferredCases <- forM cases (\RST.MkCmdCase {cmdcase_loc, cmdcase_pat = RST.XtorPat xt args, cmdcase_cmd} -> do
                   -- We lookup the types belonging to the xtor in the type declaration.
                   posTypes <- sig_args <$> lookupXtorSig xt PosRep
                   negTypes <- sig_args <$> lookupXtorSig xt NegRep
                   -- Substitute fresh unification variables for type parameters
                   let posTypes' = zonk tyParamsMap posTypes
                   let negTypes' = zonk tyParamsMap negTypes
                   -- We generate constraints for the command in the context extended
                   -- with the types from the signature.
                   cmdInferred <- withContext posTypes' (genConstraintsCommand cmdcase_cmd)
                   return (AST.MkCmdCase cmdcase_loc (AST.XtorPat xt args) cmdInferred, MkXtorSig xt negTypes'))
  case rep of
    PrdRep -> return $ AST.XCase loc rep (TyNominal defaultLoc PosRep Nothing (data_name decl) args) Nominal (fst <$> inferredCases)
    CnsRep -> return $ AST.XCase loc rep (TyNominal defaultLoc NegRep Nothing (data_name decl) args) Nominal (fst <$> inferredCases)
--
-- Refinement pattern and copattern matches
--
genConstraintsTerm (RST.XCase _ _ Refinement []) =
  -- We know that empty matches cannot be parsed as Refinement.
  -- It is therefore safe to pattern match on the head of the xtors in the other cases.
  throwGenError ["Unreachable: A refinement match needs to have at least one case."]
genConstraintsTerm (RST.XCase loc rep Refinement cases@(pmcase:_)) = do
  -- We lookup the data declaration based on the first pattern match case.
  decl <- lookupDataDecl (case (RST.cmdcase_pat pmcase) of (RST.XtorPat xt _) -> xt)
  -- We check that all cases in the pattern match belong to the type declaration.
  checkCorrectness ((\cs -> case RST.cmdcase_pat cs of RST.XtorPat xt _ -> xt) <$> cases) decl
  inferredCases <- forM cases (\RST.MkCmdCase {cmdcase_loc, cmdcase_pat = RST.XtorPat xt args , cmdcase_cmd} -> do
                       -- Generate positive and negative unification variables for all variables
                       -- bound in the pattern.
                       (uvarsPos, uvarsNeg) <- freshTVars args
                       -- Check the command in the context extended with the positive unification variables
                       cmdInferred <- withContext uvarsPos (genConstraintsCommand cmdcase_cmd)
                       -- We have to bound the unification variables with the lower and upper bounds generated
                       -- from the information in the type declaration. These lower and upper bounds correspond
                       -- to the least and greatest type translation.
                       lowerBound <- sig_args <$> (translateXtorSigLower =<< lookupXtorSig xt PosRep)
                       upperBound <- sig_args <$> (translateXtorSigUpper =<< lookupXtorSig xt NegRep)
                       genConstraintsCtxts lowerBound uvarsNeg (PatternMatchConstraint loc)
                       genConstraintsCtxts uvarsPos upperBound (PatternMatchConstraint loc)
                       -- For the type, we return the unification variables which are now bounded by the least
                       -- and greatest type translation.
                       return (AST.MkCmdCase cmdcase_loc (AST.XtorPat xt args) cmdInferred, MkXtorSig xt uvarsNeg))
  case rep of
    PrdRep -> return $ AST.XCase loc rep (TyCodata defaultLoc PosRep (Just (data_name decl)) (snd <$> inferredCases)) Refinement (fst <$> inferredCases)
    CnsRep -> return $ AST.XCase loc rep (TyData   defaultLoc NegRep (Just (data_name decl)) (snd <$> inferredCases)) Refinement (fst <$> inferredCases)
--
-- Mu and TildeMu abstractions:
--
genConstraintsTerm (RST.MuAbs loc PrdRep bs cmd) = do
  (uvpos, uvneg) <- freshTVar (ProgramVariable (fromMaybeVar bs))
  cmdInferred <- withContext [PrdCnsType CnsRep uvneg] (genConstraintsCommand cmd)
  return (AST.MuAbs loc PrdRep uvpos bs cmdInferred)
genConstraintsTerm (RST.MuAbs loc CnsRep bs cmd) = do
  (uvpos, uvneg) <- freshTVar (ProgramVariable (fromMaybeVar bs))
  cmdInferred <- withContext [PrdCnsType PrdRep uvpos] (genConstraintsCommand cmd)
  return (AST.MuAbs loc CnsRep uvneg bs cmdInferred)
--
-- Structural Destructor Application (Syntactic Sugar):
--
-- e.'D subst
--
genConstraintsTerm (RST.Dtor loc _ Structural xt destructee (subst1,PrdRep,subst2)) = do
  -- Infer the types of the arguments to the destructor.
  subst1Inferred <- genConstraintsSubst subst1
  subst2Inferred <- genConstraintsSubst subst2
  -- Infer the type of the destructee.
  destructeeInferred <- genConstraintsTerm destructee
  -- Generate a unification variable for the return type.
  (retTypePos, retTypeNeg) <- freshTVar (DtorAp loc)
  -- The type at which the destructor call happens is constructed from the
  -- (inferred) return type and the inferred types from the argument list
  let lctxt = AST.getTypArgs subst1Inferred ++ [PrdCnsType CnsRep retTypeNeg] ++ AST.getTypArgs subst2Inferred
  let codataType = TyCodata defaultLoc NegRep Nothing [MkXtorSig xt lctxt]
  -- The type of the destructee must be a subtype of the Destructor type just generated.
  addConstraint (SubType (DtorApConstraint loc) (AST.getTypeTerm destructeeInferred) codataType)
  return (AST.Dtor loc PrdRep retTypePos Structural xt destructeeInferred (subst1Inferred,PrdRep,subst2Inferred))
genConstraintsTerm (RST.Dtor loc _ Structural xt destructee (subst1,CnsRep,subst2)) = do
  -- Infer the types of the arguments to the destructor.
  subst1Inferred <- genConstraintsSubst subst1
  subst2Inferred <- genConstraintsSubst subst2
  -- Infer the type of the destructee.
  destructeeInferred <- genConstraintsTerm destructee
  -- Generate a unification variable for the return type.
  (retTypePos, retTypeNeg) <- freshTVar (DtorAp loc)
  -- The type at which the destructor call happens is constructed from the
  -- (inferred) return type and the inferred types from the argument list
  let lctxt = AST.getTypArgs subst1Inferred ++ [PrdCnsType PrdRep retTypePos] ++ AST.getTypArgs subst2Inferred
  let codataType = TyCodata defaultLoc NegRep Nothing [MkXtorSig xt lctxt]
  -- The type of the destructee must be a subtype of the Destructor type just generated.
  addConstraint (SubType (DtorApConstraint loc) (AST.getTypeTerm destructeeInferred) codataType)
  return (AST.Dtor loc CnsRep retTypeNeg Structural xt destructeeInferred (subst1Inferred,CnsRep,subst2Inferred))
--
-- Nominal Destructor Application (Syntactic Sugar):
--
-- e.D subst
--
genConstraintsTerm (RST.Dtor loc _ Nominal xt destructee (subst1,PrdRep,subst2)) = do
  -- Infer the types of the arguments to the destructor.
  subst1Inferred <- genConstraintsSubst subst1
  subst2Inferred <- genConstraintsSubst subst2
  -- Infer the type of the destructee.
  destructeeInferred <- genConstraintsTerm destructee
  -- Look up the data declaration and the xtorSig.
  decl <- lookupDataDecl xt
  xtorSig <- lookupXtorSig xt NegRep
  -- Generate fresh unification variables for type parameters
  (args, tyParamsMap) <- freshTVarsForTypeParams NegRep decl
  -- Substitute these for the type parameters in the constructor signature
  let sig_args' = zonk tyParamsMap (sig_args xtorSig)
  let ty = TyNominal defaultLoc NegRep Nothing (data_name decl) args
  -- The type of the destructee must be a subtype of the nominal type.
  addConstraint (SubType (DtorApConstraint loc) (AST.getTypeTerm destructeeInferred) ty)
  -- Split the argument list into the explicit arguments and the implicit argument.
  -- The return type is the implicit element in the xtorSig, which must be a CnsType.
  (tys1, retType, tys2) <- splitContext (length subst1) CnsRep sig_args'
  -- The argument types must be subtypes of the types declared in the xtorSig.
  genConstraintsCtxts (AST.getTypArgs (subst1Inferred ++ subst2Inferred)) (tys1 ++ tys2) (DtorArgsConstraint loc)
  return (AST.Dtor loc PrdRep retType Nominal xt destructeeInferred (subst1Inferred,PrdRep,subst2Inferred))
genConstraintsTerm (RST.Dtor loc _ Nominal xt destructee (subst1,CnsRep,subst2)) = do
  -- Infer the types of the arguments to the destructor.
  subst1Inferred <- genConstraintsSubst subst1
  subst2Inferred <- genConstraintsSubst subst2
  -- Infer the type of the destructee.
  destructeeInferred <- genConstraintsTerm destructee
  -- Look up the data declaration and the xtorSig.
  decl <- lookupDataDecl xt
  xtorSig <- lookupXtorSig xt NegRep
  -- Generate fresh unification variables for type parameters
  (args, tyParamsMap) <- freshTVarsForTypeParams NegRep decl
  -- Substitute these for the type parameters in the constructor signature
  let sig_args' = zonk tyParamsMap (sig_args xtorSig)
  let ty = TyNominal defaultLoc NegRep Nothing (data_name decl) args
  -- The type of the destructee must be a subtype of the nominal type.
  addConstraint (SubType (DtorApConstraint loc) (AST.getTypeTerm destructeeInferred) ty)
  -- Split the argument list into the explicit and implicit arguments. (Implicit argument in the middle)
  -- The return type is the implicit element in the xtorSig, which must be a PrdType.
  (tys1,retType, tys2) <- splitContext (length subst1) PrdRep sig_args'
  -- The argument types must be subtypes of the types declared in the xtorSig.
  genConstraintsCtxts (AST.getTypArgs (subst1Inferred ++ subst2Inferred)) (tys1 ++ tys2) (DtorArgsConstraint loc)
  return (AST.Dtor loc CnsRep retType Nominal xt destructeeInferred (subst1Inferred,CnsRep,subst2Inferred))
--
-- Refinement Destructor Application (Syntactic Sugar):
--
-- e.D subst
genConstraintsTerm (RST.Dtor loc _ Refinement xt destructee (subst1,PrdRep,subst2)) = do
  -- Infer the types of the arguments to the destructor.
  subst1Inferred <- genConstraintsSubst subst1
  subst2Inferred <- genConstraintsSubst subst2
  -- Infer the type of the destructee.
  destructeeInferred <- genConstraintsTerm destructee
  -- Look up the data declaration and the xtorSig.
  -- The type as well as the xtorSig have to be translated.
  decl <- lookupDataDecl xt
  -- Generate a unification variable for the return type.
  (retTypePos, retTypeNeg) <- freshTVar (DtorAp loc)
  -- The type at which the destructor call happens is constructed from the
  -- (inferred) return type and the inferred types from the argument list
  let lctxt = AST.getTypArgs subst1Inferred ++ [PrdCnsType CnsRep retTypeNeg] ++ AST.getTypArgs subst2Inferred
  let codataType = TyCodata defaultLoc NegRep (Just (data_name decl)) [MkXtorSig xt lctxt]
  -- The type of the destructee must be a subtype of the translated nominal type.
  addConstraint (SubType (DtorApConstraint loc) (AST.getTypeTerm destructeeInferred) codataType)
  -- The xtor sig has to be translated.
  xtorSigTranslated <- translateXtorSigUpper =<< lookupXtorSig xt NegRep
  -- Split the argument list into the explicit and implicit arguments. (Implicit argument in the middle)
  (tys1,_retType, tys2) <- splitContext (length subst1) CnsRep (sig_args xtorSigTranslated)
  -- The argument types must be subtypes of the greatest translation of the xtor sig.
  genConstraintsCtxts (AST.getTypArgs (subst1Inferred ++ subst2Inferred)) (tys1 ++ tys2) (DtorArgsConstraint loc)
  return (AST.Dtor loc PrdRep retTypePos Refinement xt destructeeInferred (subst1Inferred,PrdRep,subst2Inferred))
genConstraintsTerm (RST.Dtor loc _ Refinement xt destructee (subst1,CnsRep,subst2)) = do
  -- Infer the types of the arguments to the destructor.
  subst1Inferred <- genConstraintsSubst subst1
  subst2Inferred <- genConstraintsSubst subst2
  -- Infer the type of the destructee.
  destructeeInferred <- genConstraintsTerm destructee
  -- Look up the data declaration and the xtorSig.
  -- The type as well as the xtorSig have to be translated.
  decl <- lookupDataDecl xt
  -- Generate a unification variable for the return type.
  (retTypePos, retTypeNeg) <- freshTVar (DtorAp loc)
  -- The type at which the destructor call happens is constructed from the
  -- (inferred) return type and the inferred types from the argument list
  let lctxt = AST.getTypArgs subst1Inferred ++ [PrdCnsType PrdRep retTypePos] ++ AST.getTypArgs subst2Inferred
  let codataType = TyCodata defaultLoc NegRep (Just (data_name decl)) [MkXtorSig xt lctxt]
  -- The type of the destructee must be a subtype of the translated nominal type.
  addConstraint (SubType (DtorApConstraint loc) (AST.getTypeTerm destructeeInferred) codataType)
  -- The xtor sig has to be translated.
  xtorSigTranslated <- translateXtorSigUpper =<< lookupXtorSig xt NegRep
  -- Split the argument list into the explicit and implicit arguments. (Implicit argument in the middle)
  (tys1,_retType, tys2) <- splitContext (length subst1) PrdRep (sig_args xtorSigTranslated)
  -- The argument types must be subtypes of the greatest translation of the xtor sig.
  genConstraintsCtxts (AST.getTypArgs (subst1Inferred ++ subst2Inferred)) (tys1 ++ tys2) (DtorArgsConstraint loc)
  return (AST.Dtor loc CnsRep retTypeNeg Refinement xt destructeeInferred (subst1Inferred,CnsRep,subst2Inferred))
--
--
-- Structural Match (Syntactic Sugar):
--
-- case e of { 'X(xs) => e' }
--
genConstraintsTerm (RST.CaseOf loc PrdRep Structural destructee cases) = do
  destructeeInferred <- genConstraintsTerm destructee
  -- Generate a unification variable for the return type of the pattern match
  (retTypePos, retTypeNeg) <- freshTVar (PatternMatch loc)
  casesInferred <- forM cases $ \RST.MkTermCase { tmcase_loc, tmcase_pat = RST.XtorPat xt args, tmcase_term } -> do
    -- Generate positive and negative unification variables for all variables
    -- bound in the pattern.
    (argtsPos,argtsNeg) <- freshTVars args
    -- Type case term in context extended with new unification variables
    tmcase_termInferred <- withContext argtsPos (genConstraintsTerm tmcase_term)
    -- The inferred type of the term must be a subtype of the pattern match return type
    addConstraint (SubType (CaseConstraint tmcase_loc) (AST.getTypeTerm tmcase_termInferred) retTypeNeg)
    return (AST.MkTermCase tmcase_loc (AST.XtorPat xt args) tmcase_termInferred, MkXtorSig xt argtsNeg)
  -- The type of the pattern match destructee must be a subtype of the type generated by the match.
  addConstraint (SubType (PatternMatchConstraint loc) (AST.getTypeTerm destructeeInferred) (TyData defaultLoc NegRep Nothing (snd <$> casesInferred)))
  return (AST.CaseOf loc PrdRep retTypePos Structural destructeeInferred (fst <$> casesInferred))
--
-- Nominal Match (Syntactic Sugar):
--
-- case e of { X(xs) => e' }
--
genConstraintsTerm (RST.CaseOf _ PrdRep Nominal _ []) =
  -- We know that empty matches cannot be parsed as nominal.
  -- It is therefore safe to pattern match on the head of the xtors in the other cases.
  throwGenError ["Unreachable: A nominal match needs to have at least one case."]
genConstraintsTerm (RST.CaseOf loc PrdRep Nominal destructee cases@(RST.MkTermCase { tmcase_pat = RST.XtorPat xtn _ }:_)) = do
  destructeeInferred <- genConstraintsTerm destructee
  -- Lookup the type declaration in the context.
  tn@NominalDecl{..} <- lookupDataDecl xtn
  -- We check that all cases in the pattern match belong to the type declaration.
  checkCorrectness ((\cs -> case RST.tmcase_pat cs of RST.XtorPat xt _ -> xt) <$> cases) tn
  -- We check that all xtors in the type declaration are matched against.
  checkExhaustiveness ((\cs -> case RST.tmcase_pat cs of RST.XtorPat xt _ -> xt) <$> cases) tn
  -- Generate fresh unification variables for type parameters
  (args, tyParamsMap) <- freshTVarsForTypeParams NegRep tn
  -- We check that the destructee is a subtype of the Nominal Type.
  addConstraint (SubType (PatternMatchConstraint loc) (AST.getTypeTerm destructeeInferred) (TyNominal defaultLoc NegRep Nothing data_name args))
  -- We generate a unification variable for the return type.
  (retTypePos, retTypeNeg) <- freshTVar (PatternMatch loc)
  casesInferred <- forM cases $ \RST.MkTermCase { tmcase_loc, tmcase_pat = RST.XtorPat xt args, tmcase_term } -> do
    -- We look up the argument types of the xtor
    posTypes <- sig_args <$> lookupXtorSig xt PosRep
    -- Substitute fresh unification variables for type parameters
    let posTypes' = zonk tyParamsMap posTypes
    -- Type case term using new type vars
    tmcase_termInferred <- withContext posTypes' (genConstraintsTerm tmcase_term)
    -- The term must have a subtype of the pattern match return type
    addConstraint (SubType (CaseConstraint tmcase_loc) (AST.getTypeTerm tmcase_termInferred) retTypeNeg)
    return (AST.MkTermCase tmcase_loc (AST.XtorPat xt args) tmcase_termInferred)
  return (AST.CaseOf loc PrdRep retTypePos Nominal destructeeInferred casesInferred)
--
-- Refinement Match (Syntactic Sugar):
--
-- case e of { X(xs) => e' }
--
genConstraintsTerm (RST.CaseOf _ PrdRep Refinement _ []) =
  -- We know that empty matches cannot be parsed as refinement.
  -- It is therefore safe to pattern match on the head of the xtors in the other cases.
  throwGenError ["Unreachable: A refinement match needs to have at least one case."]
genConstraintsTerm (RST.CaseOf loc PrdRep Refinement destructee cases@(RST.MkTermCase { tmcase_pat = RST.XtorPat xtn _}:_)) = do
  destructeeInferred <- genConstraintsTerm destructee
  -- Lookup the type declaration in the context.
  tn@NominalDecl{..} <- lookupDataDecl xtn
  -- We check that all cases in the pattern match belong to the type declaration.
  checkCorrectness ((\cs -> case RST.tmcase_pat cs of RST.XtorPat xt _ -> xt) <$> cases) tn
  -- We generate a unification variable for the return type.
  (retTypePos, retTypeNeg) <- freshTVar (PatternMatch loc)
  casesInferred <- forM cases $ \RST.MkTermCase { tmcase_loc, tmcase_pat = RST.XtorPat xt args, tmcase_term } -> do
    -- Generate unification variables for each case arg
    (argtsPos,argtsNeg) <- freshTVars args
    -- Typecheck case term using new unification vars
    tmcase_termInferred <- withContext argtsPos (genConstraintsTerm tmcase_term)
    -- The term must have a subtype of the pattern match return type
    addConstraint (SubType (CaseConstraint tmcase_loc) (AST.getTypeTerm tmcase_termInferred) retTypeNeg)
    -- We have to bound the unification variables with the lower and upper bounds generated
    -- from the information in the type declaration. These lower and upper bounds correspond
    -- to the least and greatest type translation.
    lowerBound <- sig_args <$> (translateXtorSigLower =<< lookupXtorSig xt PosRep)
    upperBound <- sig_args <$> (translateXtorSigUpper =<< lookupXtorSig xt NegRep)
    genConstraintsCtxts lowerBound argtsNeg (PatternMatchConstraint loc)
    genConstraintsCtxts argtsPos upperBound (PatternMatchConstraint loc)
    return (AST.MkTermCase tmcase_loc (AST.XtorPat xt args) tmcase_termInferred, MkXtorSig xt argtsNeg)
  --  The destructee must have a subtype of the refinement type constructed from the cases.
  addConstraint (SubType (PatternMatchConstraint loc) (AST.getTypeTerm destructeeInferred) (TyData defaultLoc NegRep (Just data_name) (snd <$> casesInferred)))
  return (AST.CaseOf loc PrdRep retTypePos Refinement destructeeInferred (fst <$> casesInferred))
--
-- Structural Comatch (Syntactic Sugar):
--
-- cocase { 'X(xs) => e' }
--
genConstraintsTerm (RST.CocaseI loc PrdRep Structural cocases) = do
  cocasesInferred <- forM cocases $ \RST.MkTermCaseI { tmcasei_loc, tmcasei_pat = RST.XtorPatI xt (as1, (), as2), tmcasei_term } -> do
    -- Generate unification variables for each case arg
    (argtsPos1,argtsNeg1) <- freshTVars as1
    (argtsPos2,argtsNeg2) <- freshTVars as2
    -- Typecheck the term in the context extended with the unification variables.
    -- HACK: `tmcasei_term` needs to be checked in the proper context, i.e. we need to include the implicit variable even though
    -- its type is the type we are actually inferring in this call. Since the variable is implicit, it can never be referenced explicitly.
    -- Hence, the "*" type variable just serves as a placeholder to ensure that the arguments have the correct De-Bruijn indices.
    tmcasei_termInferred <- withContext (argtsPos1 ++ [PrdCnsType CnsRep (TyVar defaultLoc NegRep Nothing (MkTVar "*"))] ++ argtsPos2) (genConstraintsTerm tmcasei_term)
    return (AST.MkTermCaseI tmcasei_loc (AST.XtorPatI xt (as1, (), as2)) tmcasei_termInferred, MkXtorSig xt (argtsNeg1 ++ [PrdCnsType CnsRep $ AST.getTypeTerm tmcasei_termInferred] ++ argtsNeg2))
  return (AST.CocaseI loc PrdRep (TyCodata defaultLoc PosRep Nothing (snd <$> cocasesInferred)) Structural (fst <$> cocasesInferred))
--
-- Nominal Comatch (Syntactic Sugar):
--
-- cocase { X(xs) => e' }
--
genConstraintsTerm (RST.CocaseI _ PrdRep Nominal []) =
  throwGenError ["Unreachable: A nominal comatch needs to have at least one case."]
genConstraintsTerm (RST.CocaseI loc PrdRep Nominal cocases@(RST.MkTermCaseI {tmcasei_pat = RST.XtorPatI xtn _}:_)) = do
  -- Lookup the type declaration in the context.
  tn@NominalDecl{..} <- lookupDataDecl xtn
  -- We check that all cases in the copattern match belong to the type declaration.
  checkCorrectness ((\cs -> case RST.tmcasei_pat cs of RST.XtorPatI xt _ -> xt) <$> cocases) tn
  -- We check that all xtors in the type declaration are matched against.
  checkExhaustiveness ((\cs -> case RST.tmcasei_pat cs of RST.XtorPatI xt _ -> xt) <$> cocases) tn
  -- Generate fresh unification variables for type parameters
  (args, tyParamsMap) <- freshTVarsForTypeParams PosRep tn
  cocasesInferred <- forM cocases $ \RST.MkTermCaseI { tmcasei_loc, tmcasei_pat = RST.XtorPatI xt tmcasei_args@(as1, (),_), tmcasei_term } -> do
    -- We look up the argument types of the xtor
    posTypes <- sig_args <$> lookupXtorSig xt PosRep
    -- Substitute fresh unification variables for type parameters
    let posTypes' = zonk tyParamsMap posTypes
    -- Split the args accordingly:
    (ctxt1,retType, ctxt2) <- splitContext (length as1) CnsRep posTypes'
    -- Type case term using new type vars
    tmcasei_termInferred <- withContext (ctxt1 ++ [PrdCnsType CnsRep (TyVar defaultLoc NegRep Nothing (MkTVar "*"))] ++  ctxt2) (genConstraintsTerm tmcasei_term)
    -- The term must have a subtype of the copattern match return type
    addConstraint (SubType (CaseConstraint loc) (AST.getTypeTerm tmcasei_termInferred) retType)
    return (AST.MkTermCaseI tmcasei_loc (AST.XtorPatI xt tmcasei_args) tmcasei_termInferred)
  return (AST.CocaseI loc PrdRep (TyNominal defaultLoc PosRep Nothing data_name args) Nominal cocasesInferred)
--
-- Refinement Comatch (Syntactic Sugar):
--
-- cocase { X(xs) => e' }
--
genConstraintsTerm (RST.CocaseI _ PrdRep Refinement []) =
  throwGenError ["Unreachable: A refinement comatch needs to have at least one case."]
genConstraintsTerm (RST.CocaseI loc PrdRep Refinement cocases@(RST.MkTermCaseI {tmcasei_pat = RST.XtorPatI xtn _}:_)) = do
  -- Lookup the type declaration in the context.
  tn@NominalDecl{..} <- lookupDataDecl xtn
  -- We check that all cases in the pattern match belong to the type declaration.
  checkCorrectness ((\cs -> case RST.tmcasei_pat cs of RST.XtorPatI xt _ -> xt) <$> cocases) tn
  cocasesInferred <- forM cocases $ \RST.MkTermCaseI { tmcasei_loc, tmcasei_pat = RST.XtorPatI xt (as1, (), as2), tmcasei_term } -> do
    -- Generate unification variables for each case arg
    (argtsPos1, argtsNeg1) <- freshTVars as1
    (argtsPos2, argtsNeg2) <- freshTVars as2
    -- HACK: `tmcasei_term` needs to be checked in the proper context, i.e. we need to include the implicit variable even though
    -- its type is the type we are actually inferring in this call. Since the variable is implicit, it can never be referenced explicitly.
    -- Hence, the "*" type variable just serves as a placeholder to ensure that the arguments have the correct De-Bruijn indices.
    let argtsPos = argtsPos1 ++ [PrdCnsType CnsRep (TyVar defaultLoc NegRep Nothing (MkTVar "*"))] ++ argtsPos2
    -- Typecheck case term using new unification vars
    tmcasei_termInferred <- withContext argtsPos (genConstraintsTerm tmcasei_term)
    -- We have to bound the unification variables with the lower and upper bounds generated
    -- from the information in the type declaration. These lower and upper bounds correspond
    -- to the least and greatest type translation.
    lowerBound <- sig_args <$> (translateXtorSigLower =<< lookupXtorSig xt PosRep)
    upperBound <- sig_args <$> (translateXtorSigUpper =<< lookupXtorSig xt NegRep)

    -- HACK: Split the argument list into the explicit (lb1, lb2) and implicit arguments (_lbi). (Implicit argument in the middle)
    (lb1, retType, lb2) <- splitContext (length as1) CnsRep lowerBound
    -- HACK: Split the argument list into the explicit (ub1, ub2) and implicit arguments (_ubi). (Implicit argument in the middle)
    (ub1, _ubi, ub2) <- splitContext (length as1) CnsRep upperBound

    genConstraintsCtxts (lb1 ++ lb2) (argtsNeg1 ++ argtsNeg2) (PatternMatchConstraint loc)
    genConstraintsCtxts (argtsPos1 ++ argtsPos2) (ub1 ++ ub2) (PatternMatchConstraint loc)

    -- The term must have a subtype of the copattern match return type
    addConstraint (SubType (CaseConstraint loc) (AST.getTypeTerm tmcasei_termInferred) retType)
    return (AST.MkTermCaseI tmcasei_loc (AST.XtorPatI xt (as1, (), as2)) tmcasei_termInferred,
      MkXtorSig xt (argtsNeg1 ++ [PrdCnsType CnsRep $ AST.getTypeTerm tmcasei_termInferred] ++ argtsNeg2))
  return (AST.CocaseI loc PrdRep ( TyCodata defaultLoc PosRep (Just data_name) (snd <$> cocasesInferred)) Refinement (fst <$> cocasesInferred))
genConstraintsTerm (RST.PrimLitI64 loc i) = pure $ AST.PrimLitI64 loc i
genConstraintsTerm (RST.PrimLitF64 loc d) = pure $ AST.PrimLitF64 loc d
-- NotImplemented
genConstraintsTerm (RST.CaseOf _ CnsRep _ _ _) =
  throwGenError ["Constraint generation not implemented for CaseOf CnsRep"]
genConstraintsTerm (RST.CocaseI _ CnsRep _ _) =
  throwGenError ["Constraint generation not implemented for CocaseI CnsRep"]
genConstraintsTerm RST.Semi {} =
  throwGenError ["Constraint generation not implemented for Semi"]
genConstraintsTerm RST.CocaseOf {} =
  throwGenError ["Constraint generation not implemented for CocaseOf"]
genConstraintsTerm RST.CaseI {} =
  throwGenError ["Constraint generation not implemented for CaseI"]

genConstraintsCommand :: RST.Command -> GenM AST.Command
genConstraintsCommand (RST.ExitSuccess loc) =
  return (AST.ExitSuccess loc)
genConstraintsCommand (RST.ExitFailure loc) =
  return (AST.ExitFailure loc)
genConstraintsCommand (RST.Jump loc fv) = do
  -- Ensure that the referenced command is in scope
  _ <- lookupCommand fv
  return (AST.Jump loc fv)
genConstraintsCommand (RST.Print loc prd cmd) = do
  prd' <- genConstraintsTerm prd
  cmd' <- genConstraintsCommand cmd
  return (AST.Print loc prd' cmd')
genConstraintsCommand (RST.Read loc cns) = do
  cns' <- genConstraintsTerm cns
  addConstraint (SubType (ReadConstraint loc)  (TyNominal defaultLoc PosRep Nothing peanoNm []) (AST.getTypeTerm cns'))
  return (AST.Read loc cns')
genConstraintsCommand (RST.Apply loc t1 t2) = do
  t1' <- genConstraintsTerm t1
  t2' <- genConstraintsTerm t2
  addConstraint (SubType (CommandConstraint loc) (AST.getTypeTerm t1') (AST.getTypeTerm t2'))
  return (AST.Apply loc Nothing t1' t2')
genConstraintsCommand (RST.PrimOp loc pt op subst) = do
  substInferred <- genConstraintsSubst subst
  let substTypes = AST.getTypArgs substInferred
  case M.lookup (pt, op) primOps of
    Nothing -> throwGenError [T.pack $ "Unreachable: Signature for primitive op " ++ primOpKeyword op ++ primTypeKeyword pt ++ " not defined"]
    Just sig -> do
      _ <- genConstraintsCtxts substTypes sig (PrimOpArgsConstraint loc)
      return (AST.PrimOp loc pt op substInferred)
genConstraintsCommand RST.CaseOfI {} =
  throwGenError ["Constraint generation not implemented for CaseOfI"]
genConstraintsCommand RST.CocaseOfI {} =
  throwGenError ["Constraint generation not implemented for CocaseOfI"]
genConstraintsCommand RST.CaseOfCmd {} =
  throwGenError ["Constraint generation not implemented for CaseOfCmd"]
genConstraintsCommand RST.CocaseOfCmd {} =
  throwGenError ["Constraint generation not implemented for CocaseOfCmd"]

---------------------------------------------------------------------------------------------
-- Checking recursive terms
---------------------------------------------------------------------------------------------

genConstraintsTermRecursive :: Loc
                            -> FreeVarName
                            -> PrdCnsRep pc -> RST.Term pc
                            -> GenM (AST.Term pc)
genConstraintsTermRecursive loc fv PrdRep tm = do
  (x,y) <- freshTVar (RecursiveUVar fv)
  tm <- withTerm PrdRep fv (AST.FreeVar loc PrdRep x fv) loc (TypeScheme loc [] x) (genConstraintsTerm tm)
  addConstraint (SubType RecursionConstraint (AST.getTypeTerm tm) y)
  return tm
genConstraintsTermRecursive loc fv CnsRep tm = do
  (x,y) <- freshTVar (RecursiveUVar fv)
  tm <- withTerm CnsRep fv (AST.FreeVar loc CnsRep y fv) loc (TypeScheme loc [] y) (genConstraintsTerm tm)
  addConstraint (SubType RecursionConstraint x (AST.getTypeTerm tm))
  return tm
