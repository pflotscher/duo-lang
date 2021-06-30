module Translate.TranslateProgram 
  (compileProgram)
  where

import Translate.Translate (compile)
import Syntax.Program
import Data.Bifunctor

compileProgram :: Program a b -> Program () ()
compileProgram ps = compileDecl <$> ps
  where
    compileDecl :: Declaration a b -> Declaration () ()
    compileDecl (DefDecl isRec _ v t) = PrdDecl isRec () v $ compile t
    compileDecl decl = bimap (const ()) (const ()) decl