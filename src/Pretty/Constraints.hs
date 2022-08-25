module Pretty.Constraints () where

import Prettyprinter
import Data.List (intersperse)
import Data.Map qualified as M

import Pretty.Pretty
import Pretty.Types ()
import Syntax.TST.Types qualified as TST
import Syntax.RST.Types qualified as RST
import Syntax.RST.Types (Polarity(..))
import Syntax.CST.Names
import TypeInference.Constraints
import Syntax.CST.Kinds
import Translate.Embed

---------------------------------------------------------------------------------
-- Generated Constraints
---------------------------------------------------------------------------------

instance PrettyAnn ConstraintInfo where
  -- Primary Constraints
  prettyAnn (CtorArgsConstraint loc) = parens ("Ctor args constraint at" <+> prettyAnn loc)
  prettyAnn (DtorArgsConstraint loc) = parens ("Dtor args constraint at" <+> prettyAnn loc)
  prettyAnn (CaseConstraint loc) = parens ("Case constraint at" <+> prettyAnn loc)
  prettyAnn (PatternMatchConstraint loc) = parens ("Pattern match constraint at" <+> prettyAnn loc)
  prettyAnn (InstanceConstraint loc) = parens ("Instance constraint at" <+> prettyAnn loc) 
  prettyAnn (DtorApConstraint loc) = parens ("DtorAp constraint at" <+> prettyAnn loc)
  prettyAnn (CommandConstraint loc) = parens ("Constraint from logical command at" <+> prettyAnn loc)
  prettyAnn (ReadConstraint loc)    = parens ("Constraint from Read command at" <+> prettyAnn loc)
  prettyAnn RecursionConstraint = parens "Recursive"
  prettyAnn (PrimOpArgsConstraint loc)     = parens ("Primitive operation args constraint at" <+> prettyAnn loc)
  prettyAnn (TypeClassConstraint loc) = parens ("Type class constraint at" <+> prettyAnn loc)
  -- Derived Constraints
  prettyAnn UpperBoundConstraint           = parens "UpperBound"
  prettyAnn LowerBoundConstraint           = parens "LowerBound"
  prettyAnn XtorSubConstraint              = parens "XtorSubConstraint"
  prettyAnn IntersectionUnionSubConstraint = parens "Intersection/Union"
  prettyAnn RecTypeSubConstraint           = parens "muTypeUnfold"
  prettyAnn NominalSubConstraint           = parens "NominalSubConstraint"

instance PrettyAnn UVarProvenance where
  prettyAnn (RecursiveUVar fv) = parens ("Recursive binding:" <+> prettyAnn fv)
  prettyAnn (ProgramVariable fv) = parens ("Program variable:" <+> prettyAnn fv)
  prettyAnn (PatternMatch loc) = parens ("Return type of pattern match at" <+> prettyAnn loc)
  prettyAnn (DtorAp loc) = parens ("Result type of Dtor application at" <+> prettyAnn loc)
  prettyAnn (TypeSchemeInstance fv loc) = parens ("Instantiation of type scheme" <+> prettyAnn fv <+> "at" <+> prettyAnn loc)
  prettyAnn (TypeParameter tn tv) = parens ("Instantiation of type parameter" <+> prettyAnn tv <+> "for" <+> prettyAnn tn)
  prettyAnn (TypeClassInstance cn tv) = parens ("Instantiation for type variable"  <+> prettyAnn tv <+> "of type class" <+> prettyAnn cn)

instance PrettyAnn (Constraint ConstraintInfo) where
  prettyAnn (KindEq ann k1 k2) = 
    prettyAnn k1 <+> "~" <+> prettyAnn k2 <+> prettyAnn ann
  prettyAnn (SubType ann t1 t2) =
    prettyAnn t1 <+> "<:" <+> prettyAnn t2 <+> prettyAnn ann
  prettyAnn (TypeClassPos ann cn typ) =
    prettyAnn cn <+> prettyAnn typ <+> prettyAnn ann
  prettyAnn (TypeClassNeg ann cn typ) =
    prettyAnn cn <+> prettyAnn typ <+> prettyAnn ann

printUVar :: (UniTVar, UVarProvenance) -> Doc Annotation
printUVar (tv,prov) = prettyAnn tv <+> prettyAnn prov

instance PrettyAnn ConstraintSet where
  prettyAnn ConstraintSet { cs_constraints, cs_uvars, cs_kvars } = vsep
    [ "---------------------------------------------------------"
    , "                    Generated Constraints"
    , "---------------------------------------------------------"
    , ""
    , "Generated unification variables:"
    , nest 3 (line' <> vsep (printUVar <$> cs_uvars))
    , ""
    , nest 3 (line' <> vsep (prettyAnn <$> cs_kvars))
    , ""
    , "Generated constraints:"
    , nest 3 (line' <> vsep (prettyAnn <$> cs_constraints))
    , ""
    ]

---------------------------------------------------------------------------------
-- Solved Constraints
---------------------------------------------------------------------------------

printRSTLowerBounds :: [RST.Typ 'Pos] -> Doc Annotation
printRSTLowerBounds [] = mempty
printRSTLowerBounds lowerbounds =
  nest 3 $ vsep [ "Lower bounds:"
                ,  vsep (prettyAnn <$> lowerbounds)
                ]

printRSTUpperBounds :: [RST.Typ 'Neg] -> Doc Annotation
printRSTUpperBounds [] = mempty
printRSTUpperBounds upperbounds =
  nest 3 $ vsep [ "Upper bounds:"
                , vsep (prettyAnn <$> upperbounds)
                ]

printTSTLowerBounds :: [TST.Typ 'Pos] -> Doc Annotation
printTSTLowerBounds ls = printRSTLowerBounds (map embedTSTType ls)

printTSTUpperBounds :: [TST.Typ 'Neg] -> Doc Annotation
printTSTUpperBounds ls = printRSTUpperBounds (map embedTSTType ls)

printTypeClassConstraints :: [ClassName] -> Doc Annotation
printTypeClassConstraints [] = mempty
printTypeClassConstraints cns =
  nest 3 $ vsep [ "Type class constraints:"
                , vsep (prettyAnn <$> cns)
                ]

instance PrettyAnn VariableState where
  prettyAnn VariableState { vst_lowerbounds = []  , vst_upperbounds = []  , vst_typeclasses = []  } =
    mempty
  prettyAnn VariableState { vst_lowerbounds = []  , vst_upperbounds = []  , vst_typeclasses = cns } =
    printTypeClassConstraints cns
  prettyAnn VariableState { vst_lowerbounds = lbs , vst_upperbounds = []  , vst_typeclasses = []  } =
    printTSTLowerBounds lbs
  prettyAnn VariableState { vst_lowerbounds = lbs , vst_upperbounds = []  , vst_typeclasses = cns } =
    printTSTLowerBounds lbs <> line <> printTypeClassConstraints cns
  prettyAnn VariableState { vst_lowerbounds = []  , vst_upperbounds = ubs , vst_typeclasses = []  } =
    printTSTUpperBounds ubs
  prettyAnn VariableState { vst_lowerbounds = []  , vst_upperbounds = ubs , vst_typeclasses = cns } =
    printTSTUpperBounds ubs <> line <> printTypeClassConstraints cns
  prettyAnn VariableState { vst_lowerbounds = lbs , vst_upperbounds = ubs , vst_typeclasses = []  } =
    printTSTLowerBounds lbs <> line <> printTSTUpperBounds ubs
  prettyAnn VariableState { vst_lowerbounds = lbs , vst_upperbounds = ubs , vst_typeclasses = cns } =
    printTSTLowerBounds lbs <> line <> printTSTUpperBounds ubs <> line <> printTypeClassConstraints cns
instance PrettyAnn SolverResult where
  prettyAnn MkSolverResult { tvarSolution } = vsep
    [ "---------------------------------------------------------"
    , "                   Solved Constraints"
    , "---------------------------------------------------------"
    , ""
    , vsep $ intersperse "" (solvedConstraintsToDoc <$> M.toList tvarSolution)
    , ""
    ]
    where
      solvedConstraintsToDoc :: (UniTVar,VariableState) -> Doc Annotation
      solvedConstraintsToDoc (v, vs) = nest 3 $ vsep ["Type variable:" <+> prettyAnn v
                                                     , prettyAnn vs
                                                     ]


---------------------------------------------------------------------------------
-- Bisubstitutions
---------------------------------------------------------------------------------

prettyBisubst :: (UniTVar, (TST.Typ 'Pos, TST.Typ 'Neg)) -> Doc Annotation
prettyBisubst (v, (typ,tyn)) = nest 3 $ vsep ["Unification variable:" <+> prettyAnn v

                                             , vsep [ "+ |->" <+> prettyAnn typ
                                                    , "- |->" <+> prettyAnn tyn
                                                    ]
                                             ]

prettyRecBisubst :: (RecTVar, (TST.Typ 'Pos, TST.Typ 'Neg)) -> Doc Annotation
prettyRecBisubst (v, (typ,tyn)) = nest 3 $ vsep ["Recursive variable:" <+> prettyAnn v

                                             , vsep [ "+ |->" <+> prettyAnn typ
                                                    , "- |->" <+> prettyAnn tyn
                                                    ]
                                             ]
prettySkolBisubst :: (SkolemTVar, (TST.Typ 'Pos, TST.Typ 'Neg)) -> Doc Annotation
prettySkolBisubst (v, (typ,tyn)) = nest 3 $ vsep ["Skolem variable:" <+> prettyAnn v

                                             , vsep [ "+ |->" <+> prettyAnn typ
                                                    , "- |->" <+> prettyAnn tyn
                                                    ]
                                             ]

prettyKindSubst :: (KVar, MonoKind) -> Doc Annotation
prettyKindSubst (kv, kind) = nest 3 $ vsep ["Kind Variable:" <+> prettyAnn kv <+> "->" <+> prettyAnn kind ]

instance PrettyAnn (TST.Bisubstitution TST.UniVT) where
  prettyAnn uvsubst = vsep
    [ "---------------------------------------------------------"
    , "                 Bisubstitution (UniTVar)                "
    , "---------------------------------------------------------"
    , "" 
    , "Unification Variables: "
    , vsep $ intersperse "" (prettyBisubst <$> M.toList (fst (TST.bisubst_map uvsubst)))
    , ""
    , "Kind Variables: "
    , vsep $ intersperse "" (prettyKindSubst <$> M.toList (snd (TST.bisubst_map uvsubst)))
    ]

instance PrettyAnn (TST.Bisubstitution TST.SkolemVT) where
  prettyAnn skolvsubst = vsep 
    [ "---------------------------------------------------------"
    , "                 Bisubstitution (SkolemTVar)             "
    , "---------------------------------------------------------"
    , ""
    , vsep $ intersperse "" (prettySkolBisubst <$> M.toList (TST.bisubst_map skolvsubst))
    ]

instance PrettyAnn (TST.Bisubstitution TST.RecVT) where
  prettyAnn recvsubst = vsep
    [ "---------------------------------------------------------"
    , "                 Bisubstitution (RecTVar)                "
    , "---------------------------------------------------------"
    , ""
    , vsep $ intersperse "" (prettyRecBisubst <$> M.toList (TST.bisubst_map recvsubst))
    ]

