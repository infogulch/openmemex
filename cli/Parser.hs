module Parser where

import Control.Applicative
import Data.Semigroup ((<>))
import Options.Applicative

data CommandLine = CommandLine
  { note :: String,
    tags :: [String],
    resetDB :: Bool
  }
  deriving (Show)

commandLine :: Parser CommandLine
commandLine =
  CommandLine
    <$> strOption
      ( long "note"
          <> help "Note content"
      )
    <*> many
      ( strOption
          ( long "tag"
              <> help "Topic tag"
          )
      )
    <*> switch (long "reset" <> help "Reset databse")

optionsParser :: ParserInfo CommandLine
optionsParser =
  info
    (helper <*> commandLine)
    ( fullDesc <> progDesc "openmemex"
        <> header
          "An open source, local-first knowledge garden."
    )
