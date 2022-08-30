module Dualize.Program where

import Syntax.CST.Kinds
import Syntax.CST.Types qualified as CST
import Syntax.CST.Types (PrdCnsRep(..))
import Syntax.RST.Types qualified as RST
import Syntax.RST.Types (PolarityRep(..))
import Syntax.RST.Program qualified as RST
import Dualize.Terms
import TypeInference.GenerateConstraints.Definition (checkKind)
import Translate.Embed

flipDC :: CST.DataCodata -> CST.DataCodata
flipDC CST.Data = CST.Codata 
flipDC CST.Codata = CST.Data 

dualPolyKind :: PolyKind -> PolyKind 
dualPolyKind pk = pk 

dualDataDecl :: RST.DataDecl -> RST.DataDecl
dualDataDecl (RST.NominalDecl loc doc rntn dc pk (sigsPos,sigsNeg)) =
    RST.NominalDecl loc doc (dualRnTypeName rntn)  (flipDC dc) (dualPolyKind pk) (dualXtorSig PosRep <$> sigsPos,dualXtorSig NegRep <$> sigsNeg )
dualDataDecl (RST.RefinementDecl loc doc rntn dc pk (sigsPos,sigsNeg) (sigsPosRefined, sigsNegRefined)) =
    RST.RefinementDecl loc doc (dualRnTypeName rntn)  (flipDC dc) (dualPolyKind pk) (dualXtorSig PosRep <$> sigsPos,dualXtorSig NegRep <$> sigsNeg ) (dualXtorSig PosRep <$> sigsPosRefined,dualXtorSig NegRep <$> sigsNegRefined )

dualXtorSig ::  PolarityRep pol -> RST.XtorSig pol -> RST.XtorSig pol 
dualXtorSig pol (RST.MkXtorSig xtor lctx) = RST.MkXtorSig (dualXtorName xtor) (dualPrdCnsType pol <$> lctx)


dualPrdCnsType :: PolarityRep pol -> RST.PrdCnsType pol -> RST.PrdCnsType pol
dualPrdCnsType PosRep (RST.PrdCnsType PrdRep ty) = RST.PrdCnsType CnsRep (embedTSTType (dualType' PrdRep (checkKind ty)))
dualPrdCnsType NegRep (RST.PrdCnsType PrdRep ty) = RST.PrdCnsType CnsRep (embedTSTType (dualType' CnsRep (checkKind ty)))
dualPrdCnsType PosRep (RST.PrdCnsType CnsRep ty) = RST.PrdCnsType PrdRep (embedTSTType (dualType' CnsRep (checkKind ty)))
dualPrdCnsType NegRep (RST.PrdCnsType CnsRep ty) = RST.PrdCnsType PrdRep (embedTSTType (dualType' PrdRep (checkKind ty)))
