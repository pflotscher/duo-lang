module Syntax.Program where

import Data.Map (Map)
import qualified Data.Map as M

import Syntax.Terms
import Syntax.Types

---------------------------------------------------------------------------------
-- Program
---------------------------------------------------------------------------------

data Declaration a
  = PrdDecl FreeVarName (Term a)
  | CnsDecl FreeVarName (Term a)
  | TypDecl TypeIdentifierName TypeScheme
  deriving (Show, Eq)

data Environment = Environment
  { prdEnv :: Map FreeVarName (Term ())
  , cnsEnv :: Map FreeVarName (Term ())
  , typEnv :: Map TypeIdentifierName TypeScheme
  }

instance Semigroup Environment where
  (Environment prdEnv1 cnsEnv1 typEnv1) <> (Environment prdEnv2 cnsEnv2 typEnv2) =
    Environment { prdEnv = M.union prdEnv1 prdEnv2
                , cnsEnv = M.union cnsEnv1 cnsEnv2
                , typEnv = M.union typEnv1 typEnv2
                }

instance Monoid Environment where
  mempty = Environment
    { prdEnv = M.empty
    , cnsEnv = M.empty
    , typEnv = M.empty
    }

insertDecl :: Declaration () -> Environment -> Environment
insertDecl (PrdDecl v t) env@Environment { prdEnv } = env { prdEnv = M.insert v t prdEnv }
insertDecl (CnsDecl v t) env@Environment { cnsEnv } = env { cnsEnv = M.insert v t cnsEnv }
insertDecl (TypDecl n t) env@Environment { typEnv } = env { typEnv = M.insert n t typEnv }
