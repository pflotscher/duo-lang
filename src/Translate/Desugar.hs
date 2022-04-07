module Translate.Desugar
  ( desugarTerm
  , desugarPCTerm
  , desugarProgram
  , desugarCmd
  , desugarEnvironment
  , isDesugaredTerm
  , isDesugaredCommand
  )
  where

import Driver.Environment (Environment(..))
import Eval.Definition (EvalEnv)
import Syntax.AST.Program qualified as AST
import Syntax.AST.Terms qualified as AST
import Syntax.Core.Program qualified as Core
import Syntax.Core.Terms qualified as Core
import Syntax.Common


---------------------------------------------------------------------------------
-- Check if term is desugared
---------------------------------------------------------------------------------

isDesugaredPCTerm :: AST.PrdCnsTerm -> Bool
isDesugaredPCTerm (AST.PrdTerm tm) = isDesugaredTerm tm
isDesugaredPCTerm (AST.CnsTerm tm) = isDesugaredTerm tm

isDesugaredTerm :: AST.Term pc -> Bool
-- Core terms
isDesugaredTerm AST.BoundVar {} = True
isDesugaredTerm AST.FreeVar {} = True
isDesugaredTerm (AST.Xtor _ _ _ _ _ subst) =
  and (isDesugaredPCTerm <$> subst)
isDesugaredTerm (AST.MuAbs _ _ _ _ cmd) =
  isDesugaredCommand cmd
isDesugaredTerm (AST.XMatch _ _ _ _ cases) =
  and ((\AST.MkCmdCase { cmdcase_cmd } -> isDesugaredCommand cmdcase_cmd ) <$> cases)
isDesugaredTerm AST.PrimLitI64{} = True
isDesugaredTerm AST.PrimLitF64{} = True
-- Non-core terms
isDesugaredTerm AST.Dtor{} = False
isDesugaredTerm AST.CasePrdPrd {} = False
isDesugaredTerm AST.Cocase {} = False

isDesugaredCommand :: AST.Command -> Bool
isDesugaredCommand (AST.Apply _ _ prd cns) =
  isDesugaredTerm prd && isDesugaredTerm cns
isDesugaredCommand (AST.Print _ prd cmd) =
  isDesugaredTerm prd && isDesugaredCommand cmd
isDesugaredCommand (AST.Read _ cns) =
  isDesugaredTerm cns
isDesugaredCommand (AST.Jump _ _) = True
isDesugaredCommand (AST.ExitSuccess _) = True
isDesugaredCommand (AST.ExitFailure _) = True
isDesugaredCommand (AST.PrimOp _ _ _ subst) =
  and (isDesugaredPCTerm <$> subst)

---------------------------------------------------------------------------------
-- Desugar Terms
--
-- This translates terms into the core subset of terms.
---------------------------------------------------------------------------------

resVar :: FreeVarName
resVar = MkFreeVarName "$result"


desugarPCTerm :: AST.PrdCnsTerm -> Core.PrdCnsTerm
desugarPCTerm (AST.PrdTerm tm) = Core.PrdTerm $ desugarTerm tm
desugarPCTerm (AST.CnsTerm tm) = Core.CnsTerm $ desugarTerm tm

desugarTerm :: AST.Term pc -> Core.Term pc
desugarTerm (AST.BoundVar loc pc _annot idx) =
  Core.BoundVar loc pc idx
desugarTerm (AST.FreeVar loc pc _annot fv) =
  Core.FreeVar loc pc fv
desugarTerm (AST.Xtor loc pc _annot ns xt args) =
  Core.Xtor loc pc ns xt (desugarPCTerm <$> args)
desugarTerm (AST.MuAbs loc pc _annot bs cmd) =
  Core.MuAbs loc pc bs (desugarCmd cmd)
desugarTerm (AST.XMatch loc pc _annot ns cases) =
  Core.XMatch loc pc ns (desugarCmdCase <$> cases)
desugarTerm (AST.PrimLitI64 loc i) =
  Core.PrimLitI64 loc i
desugarTerm (AST.PrimLitF64 loc d) =
  Core.PrimLitF64 loc d
-- we want to desugar e.D(args')
-- Mu k.[(desugar e) >> D (desugar <$> args')[k] ]
desugarTerm (AST.Dtor loc _ _ ns xt t (args1,PrdRep,args2)) =
  let
    args = (desugarPCTerm <$> args1) ++ [Core.CnsTerm $ Core.FreeVar loc CnsRep resVar] ++ (desugarPCTerm <$> args2)
    cmd = Core.Apply loc Nothing (desugarTerm t)
                           (Core.Xtor loc CnsRep ns xt args)
  in
    Core.MuAbs loc PrdRep Nothing $ Core.commandClosing [(Cns, resVar)] $ Core.shiftCmd cmd
desugarTerm (AST.Dtor loc _ _ ns xt t (args1,CnsRep,args2)) =
  let
    args = (desugarPCTerm <$> args1) ++ [Core.PrdTerm $ Core.FreeVar loc PrdRep resVar] ++ (desugarPCTerm <$> args2)
    cmd = Core.Apply loc Nothing (desugarTerm t)
                                (Core.Xtor loc CnsRep ns xt args)
  in
    Core.MuAbs loc CnsRep Nothing $ Core.commandClosing [(Prd, resVar)] $ Core.shiftCmd cmd
-- we want to desugar match t { C (args) => e1 }
-- Mu k.[ (desugar t) >> match {C (args) => (desugar e1) >> k } ]
desugarTerm (AST.CasePrdPrd loc _ ns t cases)   =
  let
    desugarMatchCase (AST.MkTermCase _ xt args t) = Core.MkCmdCase loc xt args  $ Core.Apply loc Nothing (desugarTerm t) (Core.FreeVar loc CnsRep resVar)
    cmd = Core.Apply loc Nothing (desugarTerm t) (Core.XMatch loc CnsRep ns  (desugarMatchCase <$> cases))
  in
    Core.MuAbs loc PrdRep Nothing $ Core.commandClosing [(Cns, resVar)] $ Core.shiftCmd cmd
-- we want to desugar comatch { D(args) => e }
-- comatch { D(args)[k] => (desugar e) >> k }
desugarTerm (AST.Cocase loc _ ns cocases) =
  let
    desugarComatchCase (AST.MkTermCaseI _ xt (as1, (), as2) t) =
      let args = as1 ++ [(Cns,Nothing)] ++ as2 in
      Core.MkCmdCase loc xt args $ Core.Apply loc Nothing (desugarTerm t) (Core.BoundVar loc CnsRep (0,length as1))
  in
    Core.XMatch loc PrdRep ns $ desugarComatchCase <$> cocases

desugarCmdCase :: AST.CmdCase -> Core.CmdCase
desugarCmdCase (AST.MkCmdCase loc xt args cmd) = 
  Core.MkCmdCase loc xt args (desugarCmd cmd)

desugarCmd :: AST.Command -> Core.Command
desugarCmd (AST.Apply loc kind prd cns) =
  Core.Apply loc kind (desugarTerm prd) (desugarTerm cns)
desugarCmd (AST.Print loc prd cmd) =
  Core.Print loc (desugarTerm prd) (desugarCmd cmd)
desugarCmd (AST.Read loc cns) =
  Core.Read loc (desugarTerm cns)
desugarCmd (AST.Jump loc fv) =
  Core.Jump loc fv
desugarCmd (AST.ExitSuccess loc) =
  Core.ExitSuccess loc
desugarCmd (AST.ExitFailure loc) =
  Core.ExitFailure loc
desugarCmd (AST.PrimOp loc pt op subst) =
  Core.PrimOp loc pt op (desugarPCTerm <$> subst)

---------------------------------------------------------------------------------
-- Translate Program
---------------------------------------------------------------------------------

desugarDecl :: AST.Declaration -> Core.Declaration
desugarDecl (AST.PrdCnsDecl loc doc pc isRec fv annot tm) =
  Core.PrdCnsDecl loc doc pc isRec fv annot (desugarTerm tm)
desugarDecl (AST.CmdDecl loc doc fv cmd) =
  Core.CmdDecl loc doc fv (desugarCmd cmd)
desugarDecl (AST.DataDecl loc doc decl) =
  Core.DataDecl loc doc decl
desugarDecl (AST.XtorDecl loc doc dc xt args ret) =
  Core.XtorDecl loc doc dc xt args ret
desugarDecl (AST.ImportDecl loc doc mn) =
  Core.ImportDecl loc doc mn
desugarDecl (AST.SetDecl loc doc txt) =
  Core.SetDecl loc doc txt
desugarDecl (AST.TyOpDecl loc doc op prec assoc ty) =
  Core.TyOpDecl loc doc op prec assoc ty

desugarProgram :: AST.Program -> Core.Program
desugarProgram ps = desugarDecl <$> ps

desugarEnvironment :: Environment -> EvalEnv
desugarEnvironment (MkEnvironment { prdEnv, cnsEnv, cmdEnv }) = (prd,cns,cmd)
  where 
    prd = (\(tm,_,_) -> (desugarTerm tm)) <$> prdEnv
    cns = (\(tm,_,_) -> (desugarTerm tm)) <$> cnsEnv
    cmd = (\(cmd,_) -> (desugarCmd cmd)) <$> cmdEnv
