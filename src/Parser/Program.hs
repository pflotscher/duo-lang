module Parser.Program
  ( declarationP
  , programP
  ) where

import Control.Monad (void)
import Control.Monad.Reader ( MonadReader(local) )
import Text.Megaparsec hiding (State)

import Parser.Definition
import Parser.Lexer
import Parser.Terms
import Parser.Types
import Syntax.CST.Program
import Syntax.CST.Types
import Syntax.Common
import Utils
import Syntax.Kinds (Kind)

recoverDeclaration :: Parser Declaration -> Parser Declaration
recoverDeclaration = withRecovery (\err -> registerParseError err >> parseUntilKeywP >> return ParseErrorDecl)

isRecP :: Parser IsRec
isRecP = option NonRecursive (try recKwP >> pure Recursive)

annotP :: Parser (Maybe TypeScheme)
annotP = optional (try (notFollowedBy coloneq *> colon) >> typeSchemeP)

prdCnsDeclarationP :: PrdCns -> Parser Declaration
prdCnsDeclarationP pc = do
  startPos <- getSourcePos
  try (void (case pc of Prd -> prdKwP; Cns -> cnsKwP))
  recoverDeclaration $ do
    isRec <- isRecP
    (v, _pos) <- freeVarName
    annot <- annotP
    _ <- coloneq
    (tm,_) <- termP
    endPos <- semi
    pure (PrdCnsDecl (Loc startPos endPos) pc isRec v annot tm)

cmdDeclarationP :: Parser Declaration
cmdDeclarationP = do
  startPos <- getSourcePos
  try (void cmdKwP)
  recoverDeclaration $ do
    (v, _pos) <- freeVarName
    _ <- coloneq
    (cmd,_) <- commandP
    endPos <- semi
    pure (CmdDecl (Loc startPos endPos) v cmd)

importDeclP :: Parser Declaration
importDeclP = do
  startPos <- getSourcePos
  try (void importKwP)
  (mn, _) <- moduleNameP
  endPos <- semi
  return (ImportDecl (Loc startPos endPos) mn)

setDeclP :: Parser Declaration
setDeclP = do
  startPos <- getSourcePos
  try (void setKwP)
  (txt,_) <- optionP
  endPos <- semi
  return (SetDecl (Loc startPos endPos) txt)

---------------------------------------------------------------------------------
-- Nominal type declaration parser
---------------------------------------------------------------------------------

xtorDeclP :: Parser (XtorName, [(PrdCns, Typ)])
xtorDeclP = do
  (xt, _pos) <- xtorName
  (args,_) <- argListsP typP
  return (xt, args )


argListToLctxt :: [(PrdCns, Typ)] -> LinearContext
argListToLctxt = fmap convert
  where
    convert (Prd, ty) = PrdType ty
    convert (Cns, ty) = CnsType ty

combineXtor :: (XtorName, [(PrdCns, Typ)]) -> XtorSig
combineXtor (xt, args) = MkXtorSig xt (argListToLctxt args)

combineXtors :: [(XtorName, [(PrdCns, Typ)])] -> [XtorSig]
combineXtors = fmap combineXtor

dataCodataPrefixP :: Parser (IsRefined,DataCodata)
dataCodataPrefixP = do
  refined <- optional refinementKwP
  dataCodata <- (dataKwP >> return Data) <|> (codataKwP >> return Codata)
  case refined of
    Nothing -> pure (NotRefined, dataCodata)
    Just _ -> pure (Refined, dataCodata)

varianceP :: Variance -> Parser ()
varianceP Covariant = void plusSym
varianceP Contravariant = void minusSym

tParamP :: Variance -> Parser (TVar, Kind)
tParamP v = do
  _ <- varianceP v
  (tvar,_) <- tvarP
  _ <- colon
  kind <- kindP
  pure (tvar, kind)

tparamsP :: Parser TParams
tparamsP =
  (fst <$> parens inner) <|> pure (MkTParams [] [])
  where
    inner = do
      cov_ps <- tParamP Covariant `sepBy` try (comma <* notFollowedBy (varianceP Contravariant))
      if null cov_ps then
        MkTParams [] <$> tParamP Contravariant `sepBy` comma
      else do
        contra_ps <-
          try comma *> tParamP Contravariant `sepBy` comma
          <|> pure []
        pure (MkTParams cov_ps contra_ps)

dataDeclP :: Parser Declaration
dataDeclP = do
  o <- getOffset
  startPos <- getSourcePos
  (refined, dataCodata) <- dataCodataPrefixP
  recoverDeclaration $ do
    (tn, _pos) <- typeNameP
    params <- tparamsP
    if refined == Refined && not (null (allTypeVars params)) then
      region (setErrorOffset o) (fail "Parametrized refinement types are not supported, yet")
    else
      do
        _ <- colon
        knd <- kindP
        let xtorP = local (\s -> s { tvars = allTypeVars params }) xtorDeclP
        (xtors, _pos) <- braces $ xtorP `sepBy` comma
        endPos <- semi
        let decl = NominalDecl
              { data_refined = refined
              , data_name = tn
              , data_polarity = dataCodata
              , data_kind = knd
              , data_xtors = combineXtors xtors
              , data_params = params
              }

        pure (DataDecl (Loc startPos endPos) decl)

---------------------------------------------------------------------------------
-- Xtor Declaration Parser
---------------------------------------------------------------------------------

-- | Parses either "constructor" or "destructor"
ctorDtorP :: Parser DataCodata
ctorDtorP = (constructorKwP >> pure Data) <|> (destructorKwP >> pure Codata)

xtorDeclarationP :: Parser Declaration
xtorDeclarationP = do
  startPos <- getSourcePos
  dc <- ctorDtorP
  (xt, _) <- xtorName
  (args, _) <- argListsP callingConventionP
  _ <- colon
  ret <- callingConventionP
  endPos <- semi
  pure (XtorDecl (Loc startPos endPos) dc xt args ret)

---------------------------------------------------------------------------------
-- Parsing a program
---------------------------------------------------------------------------------

declarationP :: Parser Declaration
declarationP =
  prdCnsDeclarationP Prd <|>
  prdCnsDeclarationP Cns <|>
  cmdDeclarationP <|>
  importDeclP <|>
  setDeclP <|>
  dataDeclP <|>
  xtorDeclarationP

programP :: Parser Program
programP = do
  sc
  decls <- many declarationP
  eof
  return decls
