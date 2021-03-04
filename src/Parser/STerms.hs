module Parser.STerms
  ( stermP
  , commandP
  )where

import Control.Monad.Reader
import qualified Data.Map as M
import Text.Megaparsec hiding (State)


import Parser.Definition
import Parser.Lexer
import Syntax.Program
import Syntax.STerms
import Utils

--------------------------------------------------------------------------------------------
-- Symmetric Terms
--------------------------------------------------------------------------------------------

termEnvP :: PrdCnsRep pc -> Parser (STerm pc ())
termEnvP PrdRep = do
  v <- freeVarName
  prdEnv <- asks (prdEnv . parseEnv)
  case M.lookup v prdEnv of
    Just t -> return t
    Nothing -> empty
termEnvP CnsRep = do
  v <- freeVarName
  cnsEnv <- asks (cnsEnv . parseEnv)
  case M.lookup v cnsEnv of
    Just t -> return t
    Nothing -> empty

freeVar :: PrdCnsRep pc -> Parser (STerm pc ())
freeVar pc = do
  v <- freeVarName
  return (FreeVar pc v ())

numLitP :: PrdCnsRep pc -> Parser (STerm pc ())
numLitP CnsRep = empty
numLitP PrdRep = numToTerm <$> numP
  where
    numToTerm :: Int -> STerm Prd ()
    numToTerm 0 = XtorCall PrdRep (MkXtorName Structural "Zero") (MkXtorArgs [] [])
    numToTerm n = XtorCall PrdRep (MkXtorName Structural "Succ") (MkXtorArgs [numToTerm (n-1)] [])

lambdaSugar :: PrdCnsRep pc -> Parser (STerm pc ())
lambdaSugar CnsRep = empty
lambdaSugar PrdRep= do
  _ <- lexeme (symbol "\\")
  args <- argListP freeVarName freeVarName
  _ <- lexeme (symbol "=>")
  cmd <- lexeme commandP
  let args' = twiceMap (fmap (const ())) (fmap (const ())) args
  return $ XMatch PrdRep Structural [MkSCase (MkXtorName Structural "Ap") args' (commandClosing args cmd)]

-- | Parse two lists, the first in parentheses and the second in brackets.
xtorArgsP :: Parser (XtorArgs ())
xtorArgsP = do
  xs <- option [] (parens   $ (stermP PrdRep) `sepBy` comma)
  ys <- option [] (brackets $ (stermP CnsRep) `sepBy` comma)
  return $ MkXtorArgs xs ys

xtorCall :: NominalStructural -> PrdCnsRep pc -> Parser (STerm pc ())
xtorCall ns pc = do
  xt <- xtorName ns
  args <- xtorArgsP
  return $ XtorCall pc xt args

patternMatch :: NominalStructural -> PrdCnsRep pc -> Parser (STerm pc ())
patternMatch ns PrdRep = do
  _ <- symbol "comatch"
  cases <- braces $ singleCase ns `sepBy` comma
  return $ XMatch PrdRep ns cases
patternMatch ns CnsRep = do
  _ <- symbol "match"
  cases <- braces $ singleCase ns `sepBy` comma
  return $ XMatch CnsRep ns cases

singleCase :: NominalStructural -> Parser (SCase ())
singleCase ns = do
  xt <- lexeme (xtorName ns)
  args <- argListP freeVarName freeVarName
  _ <- symbol "=>"
  cmd <- lexeme commandP
  return MkSCase { scase_name = xt
                 , scase_args = twiceMap (fmap (const ())) (fmap (const ())) args -- e.g. X(x,y)[k] becomes X((),())[()]
                 , scase_cmd = commandClosing args cmd -- de brujin transformation
                 }

muAbstraction :: PrdCnsRep pc -> Parser (STerm pc ())
muAbstraction pc = do
  _ <- symbol (case pc of { PrdRep -> "mu"; CnsRep -> "mu*" })
  v <- lexeme freeVarName
  _ <- dot
  cmd <- lexeme commandP
  case pc of
    PrdRep -> return $ MuAbs pc () (commandClosingSingle CnsRep v cmd)
    CnsRep -> return $ MuAbs pc () (commandClosingSingle PrdRep v cmd)

stermP :: PrdCnsRep pc -> Parser (STerm pc ())
stermP pc = try (parens (stermP pc))
  <|> xtorCall Structural pc
  <|> xtorCall Nominal pc
  -- We put the structural pattern match parser before the nominal one, since in the case of an empty match/comatch we want to
  -- infer a structural type, not a nominal one.
  <|> try (patternMatch Structural pc) 
  <|> try (patternMatch Nominal pc)
  <|> muAbstraction pc
  <|> try (termEnvP pc) -- needs to be tried, because the parser has to consume the string, before it checks
                        -- if the variable is in the environment, which might cause it to fail
  <|> freeVar pc
  <|> numLitP pc
  <|> lambdaSugar pc

--------------------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------------------

cmdEnvP :: Parser (Command ())
cmdEnvP = do
  v <- freeVarName
  prdEnv <- asks (cmdEnv . parseEnv)
  case M.lookup v prdEnv of
    Just t -> return t
    Nothing -> empty

applyCmdP :: Parser (Command ())
applyCmdP = do
  prd <- lexeme (stermP PrdRep)
  _ <- lexeme (symbol ">>")
  cns <- lexeme (stermP CnsRep)
  return (Apply prd cns)

doneCmdP :: Parser (Command ())
doneCmdP = lexeme (symbol "Done") >> return Done

printCmdP :: Parser (Command ())
printCmdP = lexeme (symbol "Print") >> (Print <$> lexeme (stermP PrdRep))

commandP :: Parser (Command ())
commandP =
  try (parens commandP) <|>
  try cmdEnvP <|>
  doneCmdP <|>
  printCmdP <|>
  applyCmdP
