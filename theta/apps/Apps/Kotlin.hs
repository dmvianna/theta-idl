{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE ViewPatterns      #-}
module Apps.Kotlin where

import           Control.Monad           (forM_)
import           Control.Monad.Trans     (liftIO)

import qualified Data.List               as List
import           Data.Maybe              (fromMaybe)
import           Data.String.Interpolate (__i)
import qualified Data.Text               as Text
import qualified Data.Text.IO            as Text

import           Options.Applicative

import           System.Directory        (createDirectoryIfMissing)
import           System.FilePath         ((<.>), (</>), joinPath)

import qualified Theta.Import            as Theta
import           Theta.Name              (ModuleName)
import qualified Theta.Name              as Name
import qualified Theta.Types             as Theta

import           Theta.Target.Kotlin     (Kotlin (..))
import qualified Theta.Target.Kotlin     as Kotlin

import           Apps.Subcommand

kotlinCommand :: Mod CommandFields Subcommand
kotlinCommand = command "kotlin" $ runKotlin <$> opts
  where opts = info
          (kotlinOpts <**> helper)
          (fullDesc <> progDesc kotlinDescription)

kotlinDescription :: String
kotlinDescription = [__i|
  Compile a Theta module and its transitive imports to Kotlin modules.
|]

data Opts = Opts
  { moduleNames :: [ModuleName]
  , prefix      :: Maybe [Kotlin]
  , target      :: FilePath
  }

kotlinOpts :: Parser Opts
kotlinOpts = Opts <$> modules
                  <*> (fmap parsePrefix <$> importPrefix)
                  <*> (targetDirectory "the theta directory")
  where parsePrefix prefix =
          case List.find (not . Kotlin.isValidIdentifier) parts of
            Nothing          -> parts
            Just (Kotlin "") ->
              error $ "Invalid --prefix specified: ‘" <> prefix <> "’\n"
                   <> "Did you have an extra ‘.’? Leading, trailing or double \
                      \dots are not allowed."
            Just invalid     ->
              let invalidPart = Text.unpack (Kotlin.fromKotlin invalid) in
              error $ "Invalid --prefix specified: ‘" <> prefix <> "’\n"
                   <> "‘" <> invalidPart <> "’ is not a valid identifier."
          where parts = Kotlin <$> Text.splitOn "." (Text.pack prefix)

        importPrefix = optional $
          strOption ( long "prefix"
                   <> metavar "PREFIX"
                   <> help "An extra prefix to namespace all the Kotlin modules \
                           \generated by this command. This should be made up of \
                           \valid Kotlin identifiers separated by dots (.)."
                    )

runKotlin :: Opts -> Subcommand
runKotlin Opts { moduleNames, prefix, target } path = do
  liftIO $ createDirectoryIfMissing True (target </> "theta")

  modules <- traverse (Theta.getModule path) moduleNames

  -- create .avsc files for every record and variant
  forM_ (Theta.transitiveImports modules) $ \ module_ -> do
    liftIO $ generateKotlin target (fromMaybe [] prefix) module_

generateKotlin :: FilePath -> [Kotlin] -> Theta.Module -> IO ()
generateKotlin target prefix module_@Theta.Module { Theta.moduleName } = do
  let Kotlin kotlin = Kotlin.toModule prefix module_

  createDirectoryIfMissing True target
  Text.writeFile (target </> outPath </> fileName <.> "kt") kotlin

  where fileName = Text.unpack $ Name.baseName moduleName
        outPath = joinPath $ Text.unpack <$> Name.namespace moduleName
