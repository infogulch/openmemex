{-# LANGUAGE OverloadedStrings #-}

module CrawlTools where


import qualified Data.ByteString.Char8 as Str
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, catch)
import DB
import Data.List (sort)
import Data.Maybe (catMaybes)
import Data.Text (isInfixOf, isSuffixOf, pack, replace, unpack)
import Network.URI (URI, isURI, parseURI)
import OCR
import System.Directory
import System.FilePath.Posix (takeBaseName)
import System.Process
import Text.HTML.Scalpel (Scraper, chroots, scrapeURL, text)
import Text.Pretty.Simple (pPrint)
import Text.Printf
import Text.Read (readMaybe)

-- TODO - user arxiv API
arxivTransform :: String -> String
arxivTransform url = unpack . replace "arxiv.org" "export.arxiv.org" $ pack url

-- TODO - add other transformations
urlTransformations :: String -> String
urlTransformations = arxivTransform

newtype Timeout = Timeout Int

data Config = Config {
  windowSize :: (Int, Int),
  timeBudget :: Int,
  dirScreenshots :: String,
  dirThumbnails :: String,
  dirOCR :: String
} deriving Show

configDefault = Config {
  windowSize = (600, 800),
  timeBudget = 30000,
  dirScreenshots = "screenshots",
  dirThumbnails = "thumbnails",
  dirOCR = "ocr"
  }

configBig = Config {
  windowSize = (1024, 2048),
  timeBudget = 30000,
  dirScreenshots = "screenshots_lrg",
  dirThumbnails = "thumbnails_lrg",
  dirOCR = "ocr_lrg"
  }

-- TODO - use a configuration

idURL :: String -> URLType
idURL url
  -- order of pdf should come before arxivurl to take precedence
  | "pdf" `isInfixOf` pack url = PdfURL
  | "arxiv.org" `isInfixOf` pack url = ArxivURL
  | "twitter.com" `isInfixOf` pack url = TwitterURL
  | otherwise = GenericURL

parsePage :: String -> IO (Maybe WebPage)
parsePage url = fmap (\x -> if not (null x) then head x else WebPage "" "") <$> scrapeURL url title
  where
    title :: Scraper String [WebPage]
    title = do
      chroots "html" $ do
        title <- text "title"
        body <- text "body"
        return $ WebPage title body

catchAny :: IO a -> (SomeException -> IO a) -> IO a
catchAny = catch -- specialize types

scrapePage :: String -> IO (Maybe WebPage)
scrapePage url = do
  let urlType = idURL url
  case urlType of
    ArxivURL -> pure $ Just (WebPage url "")
    TwitterURL -> pure $ Just (WebPage url "")
    PdfURL -> pure $ Just (WebPage url "")
    _ -> do
      result <- parsePage url
      if result == Just (WebPage "" "") then pure Nothing else pure result

screenshot :: Timeout -> String -> Int -> IO ()
screenshot (Timeout timeout) url fileID = do
  createDirectoryIfMissing True "screenshots"
  fp <- findExecutable "chromium"
  let result = case fp of
        Just _ -> undefined
        Nothing -> error ""
  let outFile = mkScreenshotFilename fileID
  let args =
        [ printf "%ds" timeout,
          "chromium",
          "--headless",
          "--incognito",
          "--run-all-compositor-stages-before-draw",
          "--virtual-time-budget=30000",
          "--disable-gpu",
          "--window-size=600,800",
          "--hide-scrollbars",
          printf "--screenshot=%s" outFile,
          url
        ]
  (code, stdout, stderr) <- readProcessWithExitCode "timeout" args ""
  print code
  print $ "Writing to: " ++ outFile


cacheEntries :: [Entry] -> IO ()
cacheEntries entries = do
  let linkEntries = filter (isURI . content) entries
      links = urlTransformations . content <$> linkEntries
  pages <-
    mapM
      ( \url -> do
          putStrLn $ "Caching content at url: " ++ url
          catchAny (threadDelay 50000 >> scrapePage url) $ \e -> do
            putStrLn $ "Got an exception: " ++ show e
            putStrLn "Returning dummy value of Nothing"
            pure $ Just $ WebPage url ""
      )
      (filt links) -- for testing
  let cacheEntries = crawlerOutput2cache $ zip3 (filt linkEntries) (filt links) (filt pages)
  writeCache cacheEntries

appendEntries :: [Entry] -> IO ()
appendEntries entries = do
  let linkEntries = filter (isURI . content) entries
      links = urlTransformations . content <$> linkEntries
  pages <-
    mapM
      ( \url -> do
          putStrLn $ "Caching content at url: " ++ url
          catchAny (threadDelay 50000 >> scrapePage url) $ \e -> do
            putStrLn $ "Got an exception: " ++ show e
            putStrLn "Returning dummy value of Nothing"
            pure $ Just $ WebPage url ""
      )
      (filt links) -- for testing
  let cacheEntries = crawlerOutput2cache $ zip3 (filt linkEntries) (filt links) (filt pages)
  appendCache cacheEntries

filt = id

screenshotEntries :: Bool -> Timeout -> [Entry] -> IO ()
screenshotEntries deltaOnly timeout entries = do
  let linkEntries = filter (isURI . content) entries
  let links = zip (urlTransformations . content <$> linkEntries) (entryID <$> linkEntries)
  mapM_
    ( \(url, entryid) -> do
        let filename = mkScreenshotFilename entryid
        exists <- doesFileExist filename
        if (not deltaOnly || not exists) && (idURL url /= PdfURL)
          then do
            putStrLn $ "Screenshotting url: " ++ url
            catchAny (threadDelay 50000 >> screenshot timeout url entryid) $ \e -> do
              putStrLn $ "Got an exception: " ++ show e
              putStrLn "Returning dummy value of Nothing"
            putStrLn $ "Wrote " ++ filename
          else -- pure $ Just $ PageTitle url)
            putStrLn $ "Screenshot already exists or is not possible (eg a pdf) for url: " ++ url
    )
    (filt links)

ocrShots :: [Entry] -> IO ()
ocrShots entries = do
  -- make ocr output files from screenshots
  createDirectoryIfMissing True "ocr"
  -- files <- sort <$> listDirectory "screenshots"
  let files = sort ((\x -> x ++ ".png") <$> takeBaseName <$> mkScreenshotFilename <$> entryID <$> entries)
  mapM_
    ( \file -> do
        exists <- doesFileExist (ss2ocrFilename file)
        if not exists
          then do
            putStrLn $ "Running OCR for: " ++ file
            let args =
                  [ "10s",
                    "tesseract",
                    "screenshots/" ++ file,
                    ss2ocrPrefix file
                  ]
            readProcessWithExitCode "timeout" args ""
            pure ()
          else putStrLn $ "OCR already exists for file: " ++ ss2ocrFilename file
    )
    files
  -- read ocr content from file
  ocrFiles <- sort <$> listDirectory "ocr"
  ocrEntries <-
    mapM
      ( \file -> do
          content <- Str.readFile $ "ocr/" ++ file
          let entryid = readMaybe (takeBaseName file) :: Maybe Int
          case entryid of
            Just entryid -> pure $ Just (OCREntry entryid (ocr2ssFilename file) (Str.unpack content))
            Nothing -> pure Nothing
      )
      ocrFiles
  -- write entries to database
  writeOCR (catMaybes ocrEntries)

thumbnails entries = do
  -- files <- listDirectory "screenshots"
  let files = (\x -> x ++ ".png") <$> takeBaseName <$> mkScreenshotFilename <$> entryID <$> entries
  mapM_ ( \file -> do
    let outFile = (takeBaseName file) ++ "_tn.png"
    createDirectoryIfMissing True "thumbnails"
    let args = ["-resize", "30%", "-crop", "180x180+0+0", "screenshots/" ++ file, "thumbnails/" ++ outFile]
    putStrLn file
    putStrLn outFile
    (code, stdout, stderr) <- readProcessWithExitCode "convert" args ""
    putStrLn $ show code
    putStrLn stdout
    putStrLn stderr
    pure ()
    ) files

crawlAll :: IO ()
crawlAll = do
  entries <- allEntries
  screenshotEntries False (Timeout 30) entries -- False to reconstruct screenshots directory
  thumbnails entries
  -- ocrShots entries
  cacheEntries entries

crawlEntries :: [Entry] -> IO ()
crawlEntries entries = do
  screenshotEntries False (Timeout 30) entries -- False to reconstruct screenshots directory
  thumbnails entries
  -- ocrShots entries
  appendEntries entries
