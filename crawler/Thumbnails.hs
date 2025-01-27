#!/usr/bin/env stack
-- stack --resolver lts-17.4 script

module Main where

import System.Directory
import System.FilePath.Posix (takeBaseName)
import System.Process

thumbnails = do
  files <- listDirectory "screenshots"
  mapM_ ( \file -> do
    let outFile = (takeBaseName file) ++ "_tn.png"
    createDirectoryIfMissing True "thumbnails"
    let args = ["-resize", "30%", "screenshots/" ++ file, "thumbnails/" ++ outFile]
    putStrLn file
    putStrLn outFile
    (code, stdout, stderr) <- readProcessWithExitCode "convert" args ""
    pure ()
    ) files

main = do
  thumbnails
  putStrLn "Done"
