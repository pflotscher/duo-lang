module Sugar.Resugar where

import Syntax.RST.Terms qualified as RST
import Syntax.RST.Program qualified as RST
import Syntax.Core.Terms qualified as Core
import Syntax.Core.Program qualified as Core

embedPat :: Core.Pattern -> RST.Pattern
embedPat (Core.XtorPat xt args) = RST.XtorPat xt args

embedCmdCase :: Core.CmdCase -> RST.CmdCase
embedCmdCase Core.MkCmdCase {cmdcase_loc, cmdcase_pat, cmdcase_cmd } =
    RST.MkCmdCase { cmdcase_loc = cmdcase_loc
                  , cmdcase_pat = embedPat cmdcase_pat
                  , cmdcase_cmd = embedCoreCommand cmdcase_cmd
                  }

embedPCTerm :: Core.PrdCnsTerm -> RST.PrdCnsTerm
embedPCTerm (Core.PrdTerm tm) = RST.PrdTerm (embedCoreTerm tm)
embedPCTerm (Core.CnsTerm tm) = RST.CnsTerm (embedCoreTerm tm)

embedSubst :: Core.Substitution -> RST.Substitution
embedSubst = fmap embedPCTerm

embedCoreTerm :: Core.Term pc -> RST.Term pc
embedCoreTerm (Core.BoundVar loc rep idx) =
    RST.BoundVar loc rep idx
embedCoreTerm (Core.FreeVar loc rep idx) =
    RST.FreeVar loc rep idx
embedCoreTerm (Core.Xtor loc _annot rep ns xs subst) =
    RST.Xtor loc rep ns xs (embedSubst subst)
embedCoreTerm (Core.XCase loc _annot rep ns cases) =
    RST.XCase loc rep ns (embedCmdCase <$> cases)
embedCoreTerm (Core.MuAbs loc _annot rep b cmd) =
    RST.MuAbs loc rep b (embedCoreCommand cmd)
embedCoreTerm (Core.PrimLitI64 loc i) =
    RST.PrimLitI64 loc i
embedCoreTerm (Core.PrimLitF64 loc d) =
    RST.PrimLitF64 loc d


embedCoreCommand :: Core.Command -> RST.Command
embedCoreCommand (Core.Apply loc _annot _knd prd cns ) =
    RST.Apply loc (embedCoreTerm prd) (embedCoreTerm cns)
embedCoreCommand (Core.Print loc tm cmd) =
    RST.Print loc (embedCoreTerm tm) (embedCoreCommand cmd)
embedCoreCommand (Core.Read loc tm) =
    RST.Read loc (embedCoreTerm tm)
embedCoreCommand (Core.Jump loc fv) =
    RST.Jump loc fv
embedCoreCommand (Core.ExitSuccess loc) =
    RST.ExitSuccess loc
embedCoreCommand (Core.ExitFailure loc) =
    RST.ExitFailure loc
embedCoreCommand (Core.PrimOp loc ty op subst) =
    RST.PrimOp loc ty op (embedSubst subst)

embedCoreProg :: Core.Program -> RST.Program
embedCoreProg = fmap embedCoreDecl

embedCoreDecl :: Core.Declaration -> RST.Declaration
embedCoreDecl (Core.PrdCnsDecl loc doc rep isRec fv _tys tm) =
    RST.PrdCnsDecl loc doc rep isRec fv Nothing (embedCoreTerm tm)
embedCoreDecl (Core.CmdDecl loc doc fv cmd) =
    RST.CmdDecl loc doc fv (embedCoreCommand cmd)
embedCoreDecl (Core.DataDecl loc doc decl) =
    RST.DataDecl loc doc decl
embedCoreDecl (Core.XtorDecl loc doc dc xt knd eo) =
    RST.XtorDecl loc doc dc xt knd eo
embedCoreDecl (Core.ImportDecl loc doc mn) =
    RST.ImportDecl loc doc mn
embedCoreDecl (Core.SetDecl loc doc txt) =
    RST.SetDecl loc doc txt
embedCoreDecl (Core.TyOpDecl loc doc op prec assoc ty) =
    RST.TyOpDecl loc doc op prec assoc ty
embedCoreDecl (Core.TySynDecl loc doc nm ty) =
    RST.TySynDecl loc doc nm ty