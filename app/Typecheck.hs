
module Typecheck where

import Options (DebugFlags(..))
import Syntax.Common
import Driver.Driver (runCompilationModule, defaultInferenceOptions)
import Driver.Definition (defaultDriverState, execDriverM, DriverState(..), setPrintGraphOpts, setDebugOpts)
import Pretty.Errors (printLocatedError, printLocatedWarning)
import qualified Data.Text as T

runTypecheck :: DebugFlags -> ModuleName -> IO ()
runTypecheck DebugFlags { df_debug, df_printGraphs } mn = do
  (res,warnings) <- execDriverM driverState $ runCompilationModule mn
  mapM_ printLocatedWarning warnings
  case res of
    Left errs -> mapM_ printLocatedError errs
    Right (_, MkDriverState {}) -> do
      putStrLn $ "Module " <> T.unpack (unModuleName mn) <> " typechecks"
  return ()
    where
      driverState = defaultDriverState { drvOpts = infOpts }
      infOpts = (if df_printGraphs then setPrintGraphOpts else id) infOpts'
      infOpts' = (if df_debug then setDebugOpts else id) defaultInferenceOptions
