{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (threadDelay)

import Data.Time

import Data.Text(isInfixOf, pack, unpack, replace)

import Control.Exception
import  Text.HTML.Scalpel

import Network.URI (URI, isURI, parseURI)
import DB

import Text.Pretty.Simple (pPrint)

-- TODO - this doesn't work yet - need to use the query format
arxivTransform :: String -> String
arxivTransform url = unpack . replace "arxiv.org" "export.arxiv.org" $ pack url
-- arxivTransform url = "http://export.arxiv.org/api/query?id_list=cs/9901002v1"

-- TODO - add other transformations
urlTransformations = arxivTransform

idURL :: String -> URLType
idURL url = 
  if ("arxiv.org" `isInfixOf` (pack url)) then ArxivURL else 
    if ("twitter.com" `isInfixOf` (pack url)) then TwitterURL else
      if ("pdf" `isInfixOf` (pack url)) then PdfURL else
        GenericURL

getTitle :: String -> IO (Maybe PageTitle)
getTitle url = fmap (\x -> if length x > 0 then x !! 0 else PageTitle "") <$> (scrapeURL url title)
  where
      title :: Scraper String [PageTitle]
      title = do
        chroots "html" $ do
          pageTitle <- text "title"
          return $ PageTitle pageTitle

catchAny :: IO a -> (SomeException -> IO a) -> IO a
catchAny = Control.Exception.catch

router :: String -> IO (Maybe PageTitle)
router url = do
  let urlType = idURL url
  case urlType of
    ArxivURL -> pure Nothing
    PdfURL -> pure Nothing
    _ -> do
        result <- getTitle url 
        if result == Just (PageTitle "") then pure Nothing else pure result

main :: IO ()
main = do
  print $ isURI "http://www.google.com"
  print $ isURI "hello world"
  entries <- allEntries
  -- mapM_ (putStrLn . show) entries
  let linkEntries = filter (isURI . content) entries
  -- mapM_ (putStrLn . show . content) linkEntries
  let links = urlTransformations <$> content <$> linkEntries
  titles <- mapM (\url -> do
    putStrLn $ "Querying url: " ++ url
    titles <- catchAny (threadDelay 100000 >> router url) $ \e -> do
        putStrLn $ "Got an exception: " ++ show e
        putStrLn "Returning dummy value of Nothing"
        return $ Just $ PageTitle ""
    -- putStrLn $ show titles
    pure titles
    )
    (take 10 links) -- for testing
  pPrint titles