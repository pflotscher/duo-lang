
module Typecheck where

import Options (TCFlags(..))
import Syntax.Common
import Driver.Driver (runCompilationModule, defaultInferenceOptions)
import Driver.Definition (defaultDriverState, execDriverM, DriverState(..), InferenceOptions(..))
import Utils (Verbosity(..))
import Control.Monad.IO.Class (MonadIO(liftIO))
import Pretty.Pretty (ppPrintIO)
import qualified Data.Text as T

runTypecheck :: ModuleName -> TCFlags -> IO ()
runTypecheck mn TCFlags { tcf_debug, tcf_printGraphs } = do
  print tcf_debug
  (res,warnings) <- liftIO $ execDriverM driverState $ runCompilationModule mn
  mapM_ ppPrintIO warnings
  case res of
    Left errs -> mapM_ ppPrintIO errs
    Right (_, MkDriverState {}) -> do
      putStrLn $ "Module " <> T.unpack (unModuleName mn) <> " typechecks"
  return ()
  where
    driverState = defaultDriverState { drvOpts = infOpts }
    infOpts = defaultInferenceOptions { infOptsVerbosity = verbosity, infOptsPrintGraphs = tcf_printGraphs }
    verbosity = if tcf_debug then Verbose else Silent
