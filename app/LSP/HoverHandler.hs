module LSP.HoverHandler
  ( hoverHandler
  , updateHoverCache
  ) where

import Language.LSP.Types
import Language.LSP.Server
    ( requestHandler, Handlers, getConfig )
import Data.Map qualified as M
import Data.List (sortBy )
import System.Log.Logger ( debugM )
import Pretty.Pretty ( ppPrint )
import Control.Monad.IO.Class ( MonadIO(liftIO) )

import LSP.Definition ( LSPMonad, LSPConfig (MkLSPConfig), HoverMap )
import LSP.MegaparsecToLSP


import Syntax.AST.Program
import Syntax.Common
import Syntax.AST.Terms hiding (Command)
import Syntax.AST.Terms qualified as Terms
import Syntax.AST.Types
import Syntax.Kinds
import TypeTranslation

import Data.Either (fromRight)
import Data.IORef (readIORef, modifyIORef)
import Data.Text (Text)
import Data.Map (Map)
import Utils (Loc)

---------------------------------------------------------------------------------
-- Handle Type on Hover
---------------------------------------------------------------------------------

hoverHandler :: Handlers LSPMonad
hoverHandler = requestHandler STextDocumentHover $ \req responder ->  do
  let (RequestMessage _ _ _ (HoverParams (TextDocumentIdentifier uri) pos _workDone)) = req
  liftIO $ debugM "lspserver.hoverHandler" ("Received hover request: " <> show uri)
  MkLSPConfig ref <- getConfig
  cache <- liftIO $ readIORef ref
  case M.lookup uri cache of
    Nothing -> responder (Right Nothing)
    Just cache -> responder (Right (lookupInHoverMap pos cache))


updateHoverCache :: Uri -> Environment Inferred -> LSPMonad ()
updateHoverCache uri env = do
  MkLSPConfig ref <- getConfig
  liftIO $ modifyIORef ref (M.insert uri (lookupHoverEnv env))

---------------------------------------------------------------------------------
-- Computations on positions and ranges
---------------------------------------------------------------------------------

-- Define an ordering on Positions
positionOrd :: Position -> Position -> Ordering
positionOrd (Position line1 column1) (Position line2 column2) =
  case compare line1 line2 of
    LT -> LT
    EQ -> compare column1 column2
    GT -> GT

-- | Check whether the first position comes textually before the second position.
before :: Position -> Position -> Bool
before pos1 pos2 = case positionOrd pos1 pos2 of
  LT -> True
  EQ -> True
  GT -> False

-- | Check whether a given position lies within a given range
inRange :: Position -> Range -> Bool
inRange pos (Range startPos endPos) = before startPos pos && before pos endPos

-- | Order ranges according to their starting position
rangeOrd :: Range -> Range -> Ordering
rangeOrd (Range start1 _) (Range start2 _) = positionOrd start1 start2

lookupInHoverMap :: Position -> HoverMap -> Maybe Hover
lookupInHoverMap pos map =
  let
    withinRange :: [(Range, Hover)] = M.toList $ M.filterWithKey (\k _ -> inRange pos k) map
    -- | Sort them so that the range starting with the latest(!) starting position
    -- comes first.
    withinRangeOrdered = sortBy (\(r1,_) (r2,_) -> rangeOrd r2 r1) withinRange
  in
    case withinRangeOrdered of
      [] -> Nothing
      ((_,ho):_) -> Just ho


---------------------------------------------------------------------------------
-- Converting Terms to a HoverMap
---------------------------------------------------------------------------------

typeAnnotToHoverMap :: (Loc, Typ pol) -> HoverMap
typeAnnotToHoverMap (loc, ty) = M.fromList [(locToRange loc, mkHover (ppPrint ty) (locToRange loc))]



termCaseToHoverMap :: TermCase Inferred -> HoverMap
termCaseToHoverMap (MkTermCase _ _ _ tm) = termToHoverMap tm

termCaseIToHoverMap :: TermCaseI Inferred -> HoverMap
termCaseIToHoverMap (MkTermCaseI _ _ _ tm) = termToHoverMap tm

termToHoverMap :: Term pc Inferred -> HoverMap
termToHoverMap (BoundVar ext PrdRep _)           = typeAnnotToHoverMap ext
termToHoverMap (BoundVar ext CnsRep _)           = typeAnnotToHoverMap ext
termToHoverMap (FreeVar ext PrdRep _)            = typeAnnotToHoverMap ext
termToHoverMap (FreeVar ext CnsRep _)            = typeAnnotToHoverMap ext
termToHoverMap (Xtor ext PrdRep _ _ args)        = M.unions [typeAnnotToHoverMap ext, xtorArgsToHoverMap args]
termToHoverMap (Xtor ext CnsRep _ _ args)        = M.unions [typeAnnotToHoverMap ext, xtorArgsToHoverMap args]
termToHoverMap (XMatch ext PrdRep _ cases)       = M.unions $ typeAnnotToHoverMap ext : (cmdcaseToHoverMap <$> cases)
termToHoverMap (XMatch ext CnsRep _ cases)       = M.unions $ typeAnnotToHoverMap ext : (cmdcaseToHoverMap <$> cases)
termToHoverMap (MuAbs ext PrdRep _ cmd)          = M.unions [typeAnnotToHoverMap ext, commandToHoverMap cmd]
termToHoverMap (MuAbs ext CnsRep _ cmd)          = M.unions [typeAnnotToHoverMap ext, commandToHoverMap cmd]
termToHoverMap (Dtor ext _ _ e (subst1,_,subst2)) = M.unions $ [typeAnnotToHoverMap ext] <> (pctermToHoverMap <$> (PrdTerm e:(subst1 ++ subst2)))
termToHoverMap (Case ext _ e cases)           = M.unions $ [typeAnnotToHoverMap ext] <> (termCaseToHoverMap <$> cases) <> [termToHoverMap e]
termToHoverMap (Cocase ext _ cocases)           = M.unions $ [typeAnnotToHoverMap ext] <> (termCaseIToHoverMap <$> cocases)

pctermToHoverMap :: PrdCnsTerm Inferred -> HoverMap
pctermToHoverMap (PrdTerm tm) = termToHoverMap tm
pctermToHoverMap (CnsTerm tm) = termToHoverMap tm

applyToHoverMap :: Range -> Maybe Kind -> HoverMap
applyToHoverMap rng Nothing   = M.fromList [(rng, mkHover "Kind not inferred" rng)]
applyToHoverMap rng (Just cc) = M.fromList [(rng, mkHover (ppPrint cc) rng)]

commandToHoverMap :: Terms.Command Inferred -> HoverMap
commandToHoverMap (Apply loc kind prd cns) = M.unions [termToHoverMap prd, termToHoverMap cns, applyToHoverMap (locToRange loc) kind]
commandToHoverMap (Print _ prd cmd)        = M.unions [termToHoverMap prd, commandToHoverMap cmd]
commandToHoverMap (Read _ cns)             = termToHoverMap cns
commandToHoverMap (Call _ _)               = M.empty
commandToHoverMap (Done _)                 = M.empty

xtorArgsToHoverMap :: Substitution Inferred -> HoverMap
xtorArgsToHoverMap subst = M.unions (pctermToHoverMap <$> subst)

cmdcaseToHoverMap :: CmdCase Inferred -> HoverMap
cmdcaseToHoverMap (MkCmdCase {cmdcase_cmd}) = commandToHoverMap cmdcase_cmd


---------------------------------------------------------------------------------
-- Converting an environment to a HoverMap
---------------------------------------------------------------------------------

mkHover :: Text -> Range ->  Hover
mkHover txt rng = Hover (HoverContents (MarkupContent MkPlainText txt)) (Just rng)

prdEnvToHoverMap :: Map FreeVarName (Term Prd Inferred, Loc, TypeScheme Pos) -> HoverMap
prdEnvToHoverMap = M.unions . fmap f . M.toList
  where
    f (_,(e,loc,ty)) =
      let
        outerHover = M.fromList [(locToRange loc, mkHover (ppPrint ty) (locToRange loc))]
        termHover = termToHoverMap e
      in
        M.union outerHover termHover

cnsEnvToHoverMap :: Map FreeVarName (Term Cns Inferred, Loc, TypeScheme Neg) -> HoverMap
cnsEnvToHoverMap = M.unions . fmap f . M.toList
  where
    f (_,(e,loc,ty)) =
      let
        outerHover = M.fromList [(locToRange loc, mkHover (ppPrint ty) (locToRange loc))]
        termHover = termToHoverMap e
      in
        M.union outerHover termHover


cmdEnvToHoverMap :: Map FreeVarName (Terms.Command Inferred, Loc) -> HoverMap
cmdEnvToHoverMap = M.unions. fmap f . M.toList
  where
    f (_, (cmd,_)) = commandToHoverMap cmd

declEnvToHoverMap :: Environment Inferred -> [(Loc,DataDecl)] -> HoverMap
declEnvToHoverMap env ls =
  let
    ls' = (\(loc,decl) -> (locToRange loc, mkHover (printTranslation decl) (locToRange loc))) <$> ls
  in
    M.fromList ls'
  where
    printTranslation :: DataDecl -> Text
    printTranslation NominalDecl{..} = case data_polarity of
      Data   -> ppPrint $ fromRight (error "boom") $ translateTypeUpper env (TyNominal NegRep Nothing data_name [] [])
      Codata -> ppPrint $ fromRight (error "boom") $ translateTypeLower env (TyNominal PosRep Nothing data_name [] [])

lookupHoverEnv :: Environment Inferred -> HoverMap
lookupHoverEnv env@MkEnvironment { prdEnv, cnsEnv, cmdEnv, declEnv } =
  M.unions [ prdEnvToHoverMap prdEnv
           , cnsEnvToHoverMap cnsEnv
           , cmdEnvToHoverMap cmdEnv
           , declEnvToHoverMap env declEnv
           ]




