module Syntax.CST.Program where

import Data.Text (Text)

import Syntax.CST.Terms
import Syntax.CST.Types
import Syntax.Common
import Syntax.Kinds (CallingConvention)
import Utils

---------------------------------------------------------------------------------
-- Declarations
---------------------------------------------------------------------------------

data Declaration where
  PrdCnsDecl     :: Loc -> PrdCns-> IsRec -> FreeVarName -> Maybe TypeScheme -> Term                    -> Declaration
  CmdDecl        :: Loc -> FreeVarName -> Command                                                       -> Declaration
  DataDecl       :: Loc -> DataDecl                                                                     -> Declaration
  XtorDecl       :: Loc -> DataCodata -> XtorName -> [(PrdCns, CallingConvention)] -> CallingConvention -> Declaration
  ImportDecl     :: Loc -> ModuleName                                                                   -> Declaration
  SetDecl        :: Loc -> Text                                                                         -> Declaration
  ParseErrorDecl ::                                                                                        Declaration

instance Show Declaration where
  show _ = "<Show for Declaration not implemented>"

type Program = [Declaration]