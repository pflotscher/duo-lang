module Resolution.Program (resolveModule, resolveDecl) where

import Control.Monad.Reader
import Data.List.NonEmpty (NonEmpty((:|)))
import Data.List.NonEmpty qualified as NE
import Data.Map (Map)
import Data.Map qualified as M


import Errors
import Pretty.Pretty ( ppPrint )
import Resolution.Definition
import Resolution.SymbolTable
import Resolution.Terms (resolveTerm, resolveCommand, resolveInstanceCase)
import Resolution.Types (resolveTypeScheme, resolveXTorSigs, resolveTyp, resolveMethodSigs)
import Syntax.CST.Program qualified as CST
import Syntax.CST.Types qualified as CST
import Syntax.CST.Types (PrdCns(..), PrdCnsRep(..))
import Syntax.RST.Program qualified as RST
import Syntax.RST.Program (PrdCnsToPol)
import Syntax.RST.Types qualified as RST
import Syntax.RST.Types (Polarity(..), PolarityRep(..))
import Syntax.CST.Kinds
import Syntax.CST.Names
import Loc (Loc, defaultLoc)



---------------------------------------------------------------------------------
-- Data Declarations
---------------------------------------------------------------------------------

resolveXtors :: [CST.XtorSig]
           -> ResolverM ([RST.XtorSig Pos], [RST.XtorSig Neg])
resolveXtors sigs = do
    posSigs <- resolveXTorSigs PosRep sigs
    negSigs <- resolveXTorSigs NegRep sigs
    pure (posSigs, negSigs)

checkVarianceTyp :: Loc -> Variance -> PolyKind -> CST.Typ -> ResolverM ()
checkVarianceTyp _ _ tv(CST.TyUniVar loc _) =
  throwOtherError loc ["The Unification Variable " <> ppPrint tv <> " should not appear in the program at this point"]
checkVarianceTyp _ var polyKind (CST.TySkolemVar loc tVar) =
  case lookupPolyKindVariance tVar polyKind of
    -- The following line does not work correctly if the data declaration contains recursive types in the arguments of an xtor.
    Nothing   -> throwOtherError loc ["Type variable not bound by declaration: " <> ppPrint tVar]
    Just var' -> if var == var'
                 then return ()
                 else throwOtherError loc ["Variance mismatch for variable " <> ppPrint tVar <> ":"
                                          , "Found: " <> ppPrint var
                                          , "Required: " <> ppPrint var'
                                          ]
checkVarianceTyp loc var polyKind (CST.TyXData _loc' dataCodata  xtorSigs) = do
  let var' = var <> case dataCodata of
                      CST.Data   -> Covariant
                      CST.Codata -> Contravariant
  sequence_ $ checkVarianceXtor loc var' polyKind <$> xtorSigs
checkVarianceTyp loc var polyKind (CST.TyXRefined _loc' dataCodata  _tn xtorSigs) = do
  let var' = var <> case dataCodata of
                      CST.Data   -> Covariant
                      CST.Codata -> Contravariant
  sequence_ $ checkVarianceXtor loc var' polyKind <$> xtorSigs
checkVarianceTyp loc var polyKind (CST.TyApp _ (CST.TyNominal _loc' tyName) tys) = do

  NominalResult _ _ _ polyKind' <- lookupTypeConstructor loc tyName
  go ((\(v,_,_) -> v) <$> kindArgs polyKind') (NE.toList tys)
  where
    go :: [Variance] -> [CST.Typ] -> ResolverM ()
    go [] []          = return ()
    go (v:vs) (t:ts)  = do
      checkVarianceTyp loc (v <> var) polyKind t
      go vs ts
    go [] (_:_)       = throwOtherError loc ["Type Constructor " <> ppPrint tyName <> " is applied to too many arguments"]
    go (_:_) []       = throwOtherError loc ["Type Constructor " <> ppPrint tyName <> " is applied to too few arguments"]
checkVarianceTyp loc _ _ (CST.TyNominal _loc' tyName) = do
  NominalResult _ _ _ polyKnd' <- lookupTypeConstructor loc tyName
  case kindArgs polyKnd' of 
    [] -> return () 
    _ -> throwOtherError loc ["Type Constructor " <> ppPrint tyName <> " is applied to too few arguments"]
checkVarianceTyp loc var polyknd (CST.TyApp loc' (CST.TyKindAnnot _ ty) args) = checkVarianceTyp loc var polyknd (CST.TyApp loc' ty args)
checkVarianceTyp loc _ _ CST.TyApp{} = 
  throwOtherError loc ["Types can only be applied to nominal types"]
checkVarianceTyp loc var polyKind (CST.TyRec _loc' _tVar ty) =
  checkVarianceTyp loc var polyKind ty
checkVarianceTyp _loc _var _polyKind (CST.TyTop _loc') = return ()
checkVarianceTyp _loc _var _polyKind (CST.TyBot _loc') = return ()
checkVarianceTyp _loc _var _polyKind (CST.TyI64 _loc') = return ()
checkVarianceTyp _loc _var _polyKind (CST.TyF64 _loc') = return ()
checkVarianceTyp _loc _var _polyKind (CST.TyChar _loc') = return ()
checkVarianceTyp _loc _var _polyKind (CST.TyString _loc') = return ()
checkVarianceTyp loc var polyKind (CST.TyBinOpChain ty tys) = do
  -- see comments for TyBinOp
  checkVarianceTyp loc var polyKind ty
  case tys of
    ((_,_,ty') :| tys') -> do
      checkVarianceTyp loc var polyKind ty'
      sequence_ $ (\(_,_,ty) -> checkVarianceTyp loc var polyKind ty) <$> tys'
checkVarianceTyp loc var polyKind (CST.TyBinOp _loc' ty _binOp ty') = do
  -- this might need to check whether only allowed binOps are used here (i.e. forbid data Union +a +b { Union(a \/ b) } )
  -- also, might need variance check
  checkVarianceTyp loc var polyKind ty
  checkVarianceTyp loc var polyKind ty'
checkVarianceTyp loc var polyKind (CST.TyParens _loc' ty) = checkVarianceTyp loc var polyKind ty
checkVarianceTyp loc var polyKind (CST.TyKindAnnot _ ty) = checkVarianceTyp loc var polyKind ty

checkVarianceXtor :: Loc -> Variance -> PolyKind -> CST.XtorSig -> ResolverM ()
checkVarianceXtor loc var polyKind xtor = do
  sequence_ $ f <$> CST.sig_args xtor
  where
    f :: CST.PrdCnsTyp -> ResolverM ()
    f (CST.PrdType ty) = checkVarianceTyp loc (Covariant     <> var) polyKind ty
    f (CST.CnsType ty) = checkVarianceTyp loc (Contravariant <> var) polyKind ty

checkVarianceDataDecl :: Loc -> PolyKind -> CST.DataCodata -> [CST.XtorSig] -> ResolverM ()
checkVarianceDataDecl loc polyKind pol xtors = do
  case pol of
    CST.Data   -> sequence_ $ checkVarianceXtor loc Covariant     polyKind <$> xtors
    CST.Codata -> sequence_ $ checkVarianceXtor loc Contravariant polyKind <$> xtors

resolveDataDecl :: CST.DataDecl -> ResolverM RST.DataDecl
resolveDataDecl CST.MkDataDecl { data_loc, data_doc, data_refined, data_name, data_polarity, data_kind, data_xtors } = do
  case data_refined of
    CST.NotRefined -> do
      -------------------------------------------------------------------------
      -- Nominal Data Type
      -------------------------------------------------------------------------
      NominalResult data_name' _ _ _ <- lookupTypeConstructor data_loc data_name
      -- Default the kind if none was specified:
      let polyKind = case data_kind of
                        Nothing -> MkPolyKind [] (case data_polarity of CST.Data -> CBV; CST.Codata -> CBN)
                        Just knd -> knd
      checkVarianceDataDecl data_loc polyKind data_polarity data_xtors
      xtors <- resolveXtors data_xtors
      pure RST.NominalDecl { data_loc = data_loc
                           , data_doc = data_doc
                           , data_name = data_name'
                           , data_polarity = data_polarity
                           , data_kind = polyKind
                           , data_xtors = xtors
                           }
    CST.Refined -> do
      -------------------------------------------------------------------------
      -- Refinement Data Type
      -------------------------------------------------------------------------
      NominalResult data_name' _ _ _ <- lookupTypeConstructor data_loc data_name
      -- Default the kind if none was specified:
      polyKind <- case data_kind of
                        Nothing -> pure $ MkPolyKind [] (case data_polarity of CST.Data -> CBV; CST.Codata -> CBN)
                        Just knd -> case knd of
                          pk@(MkPolyKind [] _) -> pure pk
                          _                    -> throwOtherError data_loc ["Parameterized refinement types are currently not allowed."]
      -- checkVarianceDataDecl data_loc polyKind data_polarity data_xtors
      -- Lower the xtors in the adjusted environment (necessary for lowering xtors of refinement types)
      let g :: TypeNameResolve -> TypeNameResolve
          g (SynonymResult tn ty) = SynonymResult tn ty
          g (NominalResult tn dc _ polykind) = NominalResult tn dc CST.NotRefined polykind

          f :: Map ModuleName SymbolTable -> Map ModuleName SymbolTable
          f x = M.fromList (fmap (\(mn, st) -> (mn, st { typeNameMap = M.adjust g data_name (typeNameMap st) })) (M.toList x))

          h :: ResolveReader -> ResolveReader
          h r = r { rr_modules = f $ rr_modules r }
      (xtorsPos, xtorsNeg) <- local h (resolveXtors data_xtors)
      pure RST.RefinementDecl { data_loc = data_loc
                              , data_doc = data_doc
                              , data_name = data_name'
                              , data_polarity = data_polarity
                              , data_kind = polyKind
                              , data_xtors = (xtorsPos, xtorsNeg)
                              }

---------------------------------------------------------------------------------
-- Producer / Consumer Declarations
---------------------------------------------------------------------------------

resolveAnnot :: PrdCnsRep pc
             -> CST.TypeScheme
             -> ResolverM (RST.TypeScheme (PrdCnsToPol pc))
resolveAnnot PrdRep ts = resolveTypeScheme PosRep ts
resolveAnnot CnsRep ts = resolveTypeScheme NegRep ts

resolveMaybeAnnot :: PrdCnsRep pc
                  -> Maybe CST.TypeScheme
                  -> ResolverM (Maybe (RST.TypeScheme (PrdCnsToPol pc)))
resolveMaybeAnnot _ Nothing = pure Nothing
resolveMaybeAnnot pc (Just annot) = Just <$> resolveAnnot pc annot

resolvePrdCnsDeclaration :: PrdCnsRep pc
                         -> CST.PrdCnsDeclaration
                         -> ResolverM (RST.PrdCnsDeclaration pc)
resolvePrdCnsDeclaration pcrep CST.MkPrdCnsDeclaration { pcdecl_loc, pcdecl_doc, pcdecl_isRec, pcdecl_name, pcdecl_annot, pcdecl_term } = do
  pcdecl_annot' <- resolveMaybeAnnot pcrep pcdecl_annot
  pcdecl_term' <- resolveTerm pcrep pcdecl_term
  pure $ RST.MkPrdCnsDeclaration { pcdecl_loc = pcdecl_loc
                                 , pcdecl_doc = pcdecl_doc
                                 , pcdecl_pc = pcrep
                                 , pcdecl_isRec =pcdecl_isRec
                                 , pcdecl_name = pcdecl_name
                                 , pcdecl_annot = pcdecl_annot'
                                 , pcdecl_term = pcdecl_term'
                                 }

---------------------------------------------------------------------------------
-- Command Declarations
---------------------------------------------------------------------------------

resolveCommandDeclaration :: CST.CommandDeclaration
                          -> ResolverM RST.CommandDeclaration
resolveCommandDeclaration CST.MkCommandDeclaration { cmddecl_loc, cmddecl_doc, cmddecl_name, cmddecl_cmd } = do
  cmddecl_cmd' <- resolveCommand cmddecl_cmd
  pure $ RST.MkCommandDeclaration { cmddecl_loc = cmddecl_loc
                                  , cmddecl_doc = cmddecl_doc
                                  , cmddecl_name = cmddecl_name
                                  , cmddecl_cmd= cmddecl_cmd'
                                  }

---------------------------------------------------------------------------------
-- Structural Xtor Declaration
---------------------------------------------------------------------------------

resolveStructuralXtorDeclaration :: CST.StructuralXtorDeclaration
                                 -> ResolverM RST.StructuralXtorDeclaration
resolveStructuralXtorDeclaration CST.MkStructuralXtorDeclaration {strxtordecl_loc, strxtordecl_doc, strxtordecl_xdata, strxtordecl_name, strxtordecl_arity, strxtordecl_evalOrder} = do
  let evalOrder = case strxtordecl_evalOrder of
                  Just eo -> eo
                  Nothing -> case strxtordecl_xdata of CST.Data -> CBV; CST.Codata -> CBN
  pure $ RST.MkStructuralXtorDeclaration { strxtordecl_loc = strxtordecl_loc
                                         , strxtordecl_doc = strxtordecl_doc
                                         , strxtordecl_xdata = strxtordecl_xdata
                                         , strxtordecl_name = strxtordecl_name
                                         , strxtordecl_arity = strxtordecl_arity
                                         , strxtordecl_evalOrder = evalOrder
                                         }

---------------------------------------------------------------------------------
-- Type Operator Declaration
---------------------------------------------------------------------------------

resolveTyOpDeclaration :: CST.TyOpDeclaration
                       -> ResolverM RST.TyOpDeclaration
resolveTyOpDeclaration CST.MkTyOpDeclaration { tyopdecl_loc, tyopdecl_doc, tyopdecl_sym, tyopdecl_prec, tyopdecl_assoc, tyopdecl_res } = do
  NominalResult tyname' _ _ _ <- lookupTypeConstructor tyopdecl_loc tyopdecl_res
  pure RST.MkTyOpDeclaration { tyopdecl_loc = tyopdecl_loc
                             , tyopdecl_doc = tyopdecl_doc
                             , tyopdecl_sym = tyopdecl_sym
                             , tyopdecl_prec = tyopdecl_prec
                             , tyopdecl_assoc = tyopdecl_assoc
                             , tyopdecl_res = tyname'
                             }

---------------------------------------------------------------------------------
-- Type Synonym Declaration
---------------------------------------------------------------------------------

resolveTySynDeclaration :: CST.TySynDeclaration
                        -> ResolverM RST.TySynDeclaration
resolveTySynDeclaration CST.MkTySynDeclaration { tysyndecl_loc, tysyndecl_doc, tysyndecl_name, tysyndecl_res } = do
  typ <- resolveTyp PosRep tysyndecl_res
  tyn <- resolveTyp NegRep tysyndecl_res
  pure RST.MkTySynDeclaration { tysyndecl_loc = tysyndecl_loc
                              , tysyndecl_doc = tysyndecl_doc
                              , tysyndecl_name = tysyndecl_name
                              , tysyndecl_res = (typ, tyn)
                              }

---------------------------------------------------------------------------------
-- Type Class Declaration
---------------------------------------------------------------------------------

checkVarianceClassDeclaration :: Loc -> [(Variance, SkolemTVar, MonoKind)] -> [CST.XtorSig] -> ResolverM ()
checkVarianceClassDeclaration loc kinds = mapM_ (checkVarianceXtor loc Covariant (MkPolyKind kinds CBV))

resolveMethods :: [CST.XtorSig]
           -> ResolverM ([RST.MethodSig Pos], [RST.MethodSig Neg])
resolveMethods sigs = do
    posSigs <- resolveMethodSigs PosRep sigs
    negSigs <- resolveMethodSigs NegRep sigs
    pure (posSigs, negSigs)

resolveClassDeclaration :: CST.ClassDeclaration
                        -> ResolverM RST.ClassDeclaration
resolveClassDeclaration CST.MkClassDeclaration { classdecl_loc, classdecl_doc, classdecl_name, classdecl_kinds, classdecl_methods } = do
  checkVarianceClassDeclaration classdecl_loc classdecl_kinds classdecl_methods
  methodRes <- resolveMethods classdecl_methods
  pure RST.MkClassDeclaration { classdecl_loc     = classdecl_loc
                              , classdecl_doc     = classdecl_doc
                              , classdecl_name    = classdecl_name
                              , classdecl_kinds   = classdecl_kinds
                              , classdecl_methods = methodRes
                              }

---------------------------------------------------------------------------------
-- Instance Declaration
---------------------------------------------------------------------------------

resolveInstanceDeclaration :: CST.InstanceDeclaration
                        -> ResolverM RST.InstanceDeclaration
resolveInstanceDeclaration CST.MkInstanceDeclaration { instancedecl_loc, instancedecl_doc, instancedecl_name, instancedecl_class, instancedecl_typ, instancedecl_cases } = do
  typ <- resolveTyp PosRep instancedecl_typ
  tyn <- resolveTyp NegRep instancedecl_typ
  tc <- mapM resolveInstanceCase instancedecl_cases
  pure RST.MkInstanceDeclaration { instancedecl_loc = instancedecl_loc
                                 , instancedecl_doc = instancedecl_doc
                                 , instancedecl_name = instancedecl_name
                                 , instancedecl_class = instancedecl_class
                                 , instancedecl_typ = (typ, tyn)
                                 , instancedecl_cases = tc
                                 }

---------------------------------------------------------------------------------
-- Declarations
---------------------------------------------------------------------------------

resolveDecl :: CST.Declaration -> ResolverM RST.Declaration
resolveDecl (CST.PrdCnsDecl decl) = do
  case CST.pcdecl_pc decl of
    Prd -> do
      decl' <- resolvePrdCnsDeclaration PrdRep decl
      pure (RST.PrdCnsDecl PrdRep decl')
    Cns -> do
      decl' <- resolvePrdCnsDeclaration CnsRep decl
      pure (RST.PrdCnsDecl CnsRep decl')
resolveDecl (CST.CmdDecl decl) = do
  decl' <- resolveCommandDeclaration decl
  pure (RST.CmdDecl decl')
resolveDecl (CST.DataDecl decl) = do
  lowered <- resolveDataDecl decl
  pure $ RST.DataDecl lowered
resolveDecl (CST.XtorDecl decl) = do
  decl' <- resolveStructuralXtorDeclaration decl
  pure $ RST.XtorDecl decl'
resolveDecl (CST.ImportDecl decl) = do
  pure $ RST.ImportDecl decl
resolveDecl (CST.SetDecl decl) =
  pure $ RST.SetDecl decl
resolveDecl (CST.TyOpDecl decl) = do
  decl' <- resolveTyOpDeclaration decl
  pure $ RST.TyOpDecl decl'
resolveDecl (CST.TySynDecl decl) = do
  decl' <- resolveTySynDeclaration decl
  pure (RST.TySynDecl decl')
resolveDecl (CST.ClassDecl decl) = do
  decl' <- resolveClassDeclaration decl
  pure (RST.ClassDecl decl')
resolveDecl (CST.InstanceDecl decl) = do
  decl' <- resolveInstanceDeclaration decl
  pure (RST.InstanceDecl decl')
resolveDecl CST.ParseErrorDecl =
  throwOtherError defaultLoc ["Unreachable: ParseErrorDecl cannot be parsed"]

resolveModule :: CST.Module -> ResolverM RST.Module
resolveModule CST.MkModule { mod_name, mod_libpath, mod_decls } = do
  decls' <- mapM resolveDecl mod_decls
  pure RST.MkModule { mod_name = mod_name
                    , mod_libpath = mod_libpath
                    , mod_decls = decls'
                    }
