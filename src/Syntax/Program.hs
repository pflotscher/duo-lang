module Syntax.Program where

import Data.Map (Map)
import qualified Data.Map as M
import Data.Monoid (Alt(..))
import Data.Foldable (fold)
import Syntax.Terms
import Syntax.Types
import Utils

---------------------------------------------------------------------------------
-- Program
---------------------------------------------------------------------------------

type TypeIdentifierName = String -- start with uppercase

data Declaration a
  = PrdDecl FreeVarName (Term Prd a)
  | CnsDecl FreeVarName (Term Cns a)
  | TypDecl TypeIdentifierName TypeScheme
  | DataDecl DataDecl
  deriving (Show)

data Environment = Environment
  { prdEnv :: Map FreeVarName (Term Prd ())
  , cnsEnv :: Map FreeVarName (Term Cns ())
  , typEnv :: Map TypeIdentifierName TypeScheme
  , declEnv :: [DataDecl]
  }

instance Semigroup Environment where
  (Environment prdEnv1 cnsEnv1 typEnv1 declEnv1) <> (Environment prdEnv2 cnsEnv2 typEnv2 declEnv2) =
    Environment { prdEnv = M.union prdEnv1 prdEnv2
                , cnsEnv = M.union cnsEnv1 cnsEnv2
                , typEnv = M.union typEnv1 typEnv2
                , declEnv = declEnv1 ++ declEnv2
                }

instance Monoid Environment where
  mempty = Environment
    { prdEnv = M.empty
    , cnsEnv = M.empty
    , typEnv = M.empty
    , declEnv = []
    }

insertDecl :: Declaration () -> Environment -> Environment
insertDecl (PrdDecl v t)  env@Environment { prdEnv }  = env { prdEnv  = M.insert v t prdEnv }
insertDecl (CnsDecl v t)  env@Environment { cnsEnv }  = env { cnsEnv  = M.insert v t cnsEnv }
insertDecl (TypDecl n t)  env@Environment { typEnv }  = env { typEnv  = M.insert n t typEnv }
insertDecl (DataDecl dcl) env@Environment { declEnv } = env { declEnv = dcl : declEnv }

envToXtorMap :: Environment -> Map XtorName (Twice [SimpleType])
envToXtorMap Environment { declEnv } = M.unions xtorMaps
  where
    xtorMaps = xtorSigsToAssocList <$> declEnv
    xtorSigsToAssocList NominalDecl { data_xtors } =
      M.fromList ((\MkXtorSig { sig_name, sig_args } ->(sig_name, sig_args)) <$> data_xtors)

lookupXtor :: XtorName -> Environment -> Maybe TypeName
lookupXtor xt Environment { declEnv } = firstJust (xtorInDecl <$> declEnv)
  where
    xtorInDecl :: DataDecl -> Maybe TypeName
    xtorInDecl NominalDecl { data_name, data_xtors } | xt `elem` (sig_name <$> data_xtors) = Just data_name
                                              | otherwise = Nothing
    firstJust :: [Maybe TypeName] -> Maybe TypeName
    firstJust x = getAlt (fold ( Alt <$> x))
