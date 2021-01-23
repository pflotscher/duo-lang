module Parser.Program where

import Control.Monad.Reader
import Parser.Definition
import Parser.Lexer
import Parser.Terms
import Parser.Types
import Syntax.Program
import Syntax.Types
import Syntax.Terms

import Text.Megaparsec hiding (State)
---------------------------------------------------------------------------------
-- Parsing a program
---------------------------------------------------------------------------------

declarationP :: Parser (Declaration ())
declarationP = prdDeclarationP <|> cnsDeclarationP <|> cmdDeclarationP <|> typeDeclarationP <|> dataDeclP

prdDeclarationP :: Parser (Declaration ())
prdDeclarationP = do
  _ <- try $ lexeme (symbol "prd")
  v <- freeVarName
  _ <- lexeme (symbol ":=")
  t <- lexeme (termP PrdRep)
  _ <- symbol ";"
  return (PrdDecl v t)

cnsDeclarationP :: Parser (Declaration ())
cnsDeclarationP = do
  _ <- try $ lexeme (symbol "cns")
  v <- freeVarName
  _ <- lexeme (symbol ":=")
  t <- lexeme (termP CnsRep)
  _ <- symbol ";"
  return (CnsDecl v t)

cmdDeclarationP :: Parser (Declaration ())
cmdDeclarationP = do
  _ <- try $ lexeme (symbol "cmd")
  v <- freeVarName
  _ <- lexeme (symbol ":=")
  t <- lexeme commandP
  _ <- symbol ";"
  return (CmdDecl v t)

typeDeclarationP :: Parser (Declaration ())
typeDeclarationP = do
  v <- typeIdentifierName
  _ <- symbol ":="
  t <- typeSchemeP
  return (TypDecl v t)

-- Multiple definitions seperated by ';'. Later definition may depend on earlier ones
environmentP :: Parser Syntax.Program.Environment
environmentP = (eof >> asks parseEnv) <|> do
  decl <- sc >> declarationP
  local (\pr@ParseReader {parseEnv} -> pr { parseEnv = insertDecl decl parseEnv }) environmentP

---------------------------------------------------------------------------------
-- Nominal type declaration parser
---------------------------------------------------------------------------------

dataDeclP :: Parser (Declaration ())
dataDeclP = DataDecl <$> dataDeclP'
  where
    dataDeclP' :: Parser DataDecl
    dataDeclP' = do
      dataCodata <- dataCodataDeclP
      tn <- typeNameP
      xtors <- braces $ xtorDeclP `sepBy` comma
      _ <- symbol ";"
      return NominalDecl
        { data_name = tn
        , data_polarity = dataCodata
        , data_xtors = xtors
        }

    dataCodataDeclP :: Parser DataCodata
    dataCodataDeclP = (symbol "data" >> return Data) <|> (symbol "codata" >> return Codata)

    xtorDeclP :: Parser (XtorSig SimpleType)
    xtorDeclP = do
      xt <- xtorName Nominal
      args <- argListP (lexeme simpleTypeP) (lexeme simpleTypeP)
      return (MkXtorSig xt args)



