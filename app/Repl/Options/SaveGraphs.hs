module Repl.Options.SaveGraphs (saveOption) where

import Control.Monad.State ( MonadIO(liftIO), gets )
import Data.GraphViz
    ( isGraphvizInstalled, runGraphviz, GraphvizOutput(XDot, Jpeg) )
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (createDirectoryIfMissing, getCurrentDirectory)
import System.FilePath ((</>), (<.>))

import Text.Megaparsec ( errorBundlePretty )
import Parser.Parser ( runInteractiveParser, atermP, stermP, typeSchemeP )
import Pretty.Pretty ( ppPrint, PrettyAnn )
import Pretty.Program ()
import Pretty.TypeAutomata (typeAutToDot)
import Repl.Repl
    ( Option(..),
      Repl,
      ReplState(replEnv, typeInfOpts),
      prettyRepl,
      prettyText,
      fromRight )
import Syntax.Program ( IsRec(NonRecursive) )
import Syntax.STerms ( PrdCnsRep(PrdRep) )
import Syntax.Types ( PolarityRep(PosRep) )
import TypeAutomata.Definition ( TypeAut', EdgeLabelNormal )
import TypeAutomata.ToAutomaton (typeToAut)
import TypeInference.Driver
    ( execDriverM,
      DriverState(DriverState),
      inferATermTraced,
      inferSTermTraced,
      TypeInferenceTrace(trace_typeAut, trace_typeAutDet,
                         trace_typeAutDetAdms, trace_minTypeAut, trace_resType) )
import Utils

-- Save

saveCmd :: Text -> Repl ()
saveCmd s = do
  env <- gets replEnv
  opts <- gets typeInfOpts
  case runInteractiveParser (typeSchemeP PosRep) s of
    Right ty -> do
      aut <- fromRight (typeToAut ty)
      saveGraphFiles "gr" aut
    Left err1 -> case runInteractiveParser (stermP PrdRep) s of
      Right (tloc,loc) -> do
        let inferenceAction = inferSTermTraced NonRecursive (Loc loc loc) "" PrdRep tloc
        traceEither <- liftIO $ execDriverM (DriverState opts env) inferenceAction
        case fst <$> traceEither of
          Right trace -> saveFromTrace trace
          Left err2 -> case runInteractiveParser atermP s of
            Right (tloc,loc) -> do
              let inferenceAction = inferATermTraced NonRecursive (Loc loc loc) "" tloc
              traceEither <- liftIO $ execDriverM (DriverState opts env) inferenceAction
              trace <- fromRight $ fst <$> traceEither
              saveFromTrace trace
            Left err3 -> saveParseError (errorBundlePretty err1) err2 (errorBundlePretty err3)
      Left err2 -> case runInteractiveParser atermP s of
        Right (tloc,loc) -> do
          let inferenceAction = inferATermTraced NonRecursive (Loc loc loc) "" tloc
          traceEither <- liftIO $ execDriverM (DriverState opts env) inferenceAction
          trace <- fromRight $ fst <$> traceEither
          saveFromTrace trace
        Left err3 -> saveParseError (errorBundlePretty err1) (errorBundlePretty err2) (errorBundlePretty err3)

saveFromTrace :: TypeInferenceTrace pol -> Repl ()
saveFromTrace trace = do
  saveGraphFiles "0_typeAut" (trace_typeAut trace)
  saveGraphFiles "1_typeAutDet" (trace_typeAutDet trace)
  saveGraphFiles "2_typeAutDetAdms" (trace_typeAutDetAdms trace)
  saveGraphFiles "3_minTypeAut" (trace_minTypeAut trace)
  prettyText (" :: " <> ppPrint (trace_resType trace))

saveParseError :: PrettyAnn a => String -> a -> String -> Repl ()
saveParseError e1 e2 e3 = do
  prettyText (T.unlines [ "Type parsing error:", ppPrint e1
                        , "STerm parsing error:", ppPrint e2
                        , "ATerm parsing error:", ppPrint e3 ])

saveGraphFiles :: String -> TypeAut' EdgeLabelNormal f pol -> Repl ()
saveGraphFiles fileName aut = do
  let graphDir = "graphs"
  let fileUri = "  file://"
  let jpg = "jpg"
  let xdot = "xdot"
  dotInstalled <- liftIO $ isGraphvizInstalled
  if dotInstalled
    then do
      liftIO $ createDirectoryIfMissing True graphDir
      currentDir <- liftIO $ getCurrentDirectory
      _ <- liftIO $ runGraphviz (typeAutToDot aut) Jpeg (graphDir </> fileName <.> jpg)
      _ <- liftIO $ runGraphviz (typeAutToDot aut) (XDot Nothing) (graphDir </> fileName <.> xdot)
      prettyRepl (fileUri ++ currentDir </> graphDir </> fileName <.> jpg)
    else do
      prettyText "Cannot execute command: graphviz executable not found in path."


saveOption :: Option
saveOption = Option
  { option_name = "save"
  , option_cmd = saveCmd
  , option_help = ["Save generated type automata to disk as jpgs."]
  , option_completer = Nothing
  }
