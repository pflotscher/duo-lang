module LSP where

import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO, MonadIO)
import Control.Monad.IO.Unlift (MonadUnliftIO)
import Language.LSP.Server
import Language.LSP.Types
import Language.LSP.VFS
import System.Exit ( exitSuccess )
import qualified Data.Text as T
import qualified Data.Text.IO as T

import TypeInference.GenerateConstraints.Definition
    ( InferenceMode(InferNominal) )
import TypeInference.InferProgram ( inferProgram )
import Parser.Definition ( runFileParser )
import Parser.Program ( programP )

runLSP :: IO ()
runLSP = initVFS $ \vfs -> runServer (definition vfs) >> return ()

-- Server Configuration

data LSPConfig = MkLSPConfig
  { lspConfigVFS :: VFS }

newtype LSPMonad a = MkLSPMonad { unLSPMonad :: LspT LSPConfig IO a }
  deriving (Functor, Applicative, Monad, MonadIO, MonadUnliftIO, MonadLsp LSPConfig)

serverOptions :: Options
serverOptions = Options
  { textDocumentSync = Just (TextDocumentSyncOptions (Just True) (Just TdSyncIncremental) Nothing Nothing Nothing)
  , completionTriggerCharacters = Nothing
  , completionAllCommitCharacters = Nothing
  , signatureHelpTriggerCharacters = Nothing
  , signatureHelpRetriggerCharacters = Nothing
  , codeActionKinds = Nothing
  , documentOnTypeFormattingTriggerCharacters = Nothing
  , executeCommandCommands = Nothing
  , serverInfo = Nothing
  }

definition :: VFS -> ServerDefinition LSPConfig
definition vfs = ServerDefinition
  { defaultConfig = MkLSPConfig vfs
  , onConfigurationChange = \config _ -> pure config
  , doInitialize = \env _req -> pure $ Right env
  , staticHandlers = handlers
  , interpretHandler = \env -> Iso (runLspT env . unLSPMonad) liftIO
  , options = serverOptions
  }

initialize :: LanguageContextEnv LSPConfig
           -> Message Initialize
           -> IO (Either ResponseError ())
initialize _ _ = return $ Right ()

-- All Handlers

handlers :: Handlers LSPMonad
handlers = mconcat [ initializedHandler
                   , exitHandler
                   , shutdownHandler
                   , didOpenHandler
                   , didChangeHandler
                   , didCloseHandler
                   ]

-- Initialization Handlers

initializedHandler :: Handlers LSPMonad
initializedHandler = notificationHandler SInitialized $ \_notif -> do
  let msg = "LSP Server for DualSub Initialized!"
  sendNotification SWindowShowMessage (ShowMessageParams MtInfo msg)

-- Exit + Shutdown Handlers

exitHandler :: Handlers LSPMonad
exitHandler = notificationHandler SExit $ \_notif -> do
  liftIO exitSuccess

shutdownHandler :: Handlers LSPMonad
shutdownHandler = requestHandler SShutdown $ \_re responder -> do
  let rsp = Right Empty
  responder rsp
  liftIO exitSuccess

-- File Open + Change + Close Handlers

didOpenHandler :: Handlers LSPMonad
didOpenHandler = notificationHandler STextDocumentDidOpen $ \notif -> do
  let (NotificationMessage _ _ (DidOpenTextDocumentParams (TextDocumentItem uri _ _ _))) = notif
  sendInfo $ "Opened file: " <> (T.pack $ show uri)
  forM_ (uriToFilePath uri) publishErrors

didChangeHandler :: Handlers LSPMonad
didChangeHandler = notificationHandler STextDocumentDidChange $ \notif -> do
  let (NotificationMessage _ _ (DidChangeTextDocumentParams (VersionedTextDocumentIdentifier uri _) _)) = notif
  sendInfo $ "Changed file:" <> (T.pack $ show uri)
  forM_ (uriToFilePath uri) publishErrors

didCloseHandler :: Handlers LSPMonad
didCloseHandler = notificationHandler STextDocumentDidClose $ \_notif -> do
  return ()

-- Publish diagnostics for File

publishErrors :: FilePath -> LSPMonad ()
publishErrors fp = do
  file <- liftIO $ T.readFile fp
  let decls = runFileParser fp programP file
  case decls of
    Left _err -> do
      sendError "Parsing error!"
    Right decls -> do
      let res = inferProgram decls InferNominal
      case res of
        Left _err -> do
          sendError "Typeinference error!"
        Right _ -> do
          sendInfo $ "No errors in " <> T.pack fp <> "!"

sendInfo :: T.Text -> LSPMonad ()
sendInfo msg = sendNotification SWindowShowMessage (ShowMessageParams MtInfo msg)

sendWarning :: T.Text -> LSPMonad ()
sendWarning msg = sendNotification SWindowShowMessage (ShowMessageParams MtWarning  msg)

sendError :: T.Text -> LSPMonad ()
sendError msg = sendNotification SWindowShowMessage (ShowMessageParams MtError msg)
