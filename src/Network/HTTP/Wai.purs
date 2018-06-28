module Network.HTTP.Wai
  ( Application
  , Middleware
  , toWaiRequest
  , reqPathInfo
  , reqHeaders
  , reqHttpVersion
  , reqQuery
  , reqBody
  , reqMethod
  , responseFile
  , responseBuffer
  , responseStream
  , responseStrUtf8
  , responseStatus
  , responseHeaders
  , modifyResponse
  , ifRequest
  , module H
  , module Network.HTTP.Wai.Internal
  ) where

import Prelude

import Data.Either (hush)
import Data.List (List(..), (:), fromFoldable)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as S
import Data.Tuple (Tuple)

import Effect (Effect)

import Foreign.Object as FO

import Node.Buffer (Buffer)
import Node.Encoding (Encoding(UTF8))
import Node.HTTP as NH
import Node.Stream (Readable)

import Text.Parsing.Parser (runParser)

import URI.Query (Query)
import URI.Query as Q

import Network.HTTP.Types as H
import Network.HTTP.Wai.Internal (Request(..), Response(..), FilePath, FilePart(..), ResponseReceived(..))


type Application =
  Request -> (Response -> Effect ResponseReceived) -> Effect ResponseReceived

type Middleware = Application -> Application

reqPathInfo :: Request -> List String
reqPathInfo (Request s) = s.pathInfo

reqHeaders :: Request -> H.RequestHeaders
reqHeaders (Request s) = s.headers

reqHttpVersion :: Request -> H.HttpVersion
reqHttpVersion (Request s) = s.httpVersion

reqQuery :: Request -> Maybe Query
reqQuery (Request s) = s.query

reqMethod :: Request -> H.Method
reqMethod (Request s) = s.method

reqBody :: Request -> Readable ()
reqBody (Request s) = s.body

responseFile :: H.Status -> H.ResponseHeaders -> FilePath -> Maybe FilePart -> Response
responseFile = ResponseFile

responseBuffer :: H.Status -> H.ResponseHeaders -> Buffer -> Response
responseBuffer = ResponseBuffer

responseString :: H.Status -> H.ResponseHeaders -> Encoding -> String -> Response
responseString = ResponseString

responseStream
  :: H.Status
  -> H.ResponseHeaders
  -> (forall a. Readable a)
  -> Response
responseStream = ResponseStream

responseStrUtf8 :: H.Status -> H.ResponseHeaders -> String -> Response
responseStrUtf8 s h = responseString s h UTF8

responseStatus :: Response -> H.Status
responseStatus (ResponseFile s _ _ _)   = s
responseStatus (ResponseStream s _ _)   = s
responseStatus (ResponseBuffer s _ _)   = s
responseStatus (ResponseString s _ _ _) = s

responseHeaders :: Response -> H.ResponseHeaders
responseHeaders (ResponseFile _ h _ _)   = h
responseHeaders (ResponseStream _ h _)   = h
responseHeaders (ResponseBuffer _ h _)   = h
responseHeaders (ResponseString _ h _ _) = h

modifyResponse :: (Response -> Response) -> Middleware
modifyResponse f app req respond = app req $ respond <<< f

ifRequest :: (Request -> Boolean) -> Middleware -> Middleware
ifRequest rpred middle app req = if rpred req then middle app req else app req

parsedQuery :: String -> Maybe Query
parsedQuery = hush <<< (flip runParser) Q.parser

pathSegments :: String -> List String
pathSegments ""  = Nil
pathSegments "/" = Nil
pathSegments s   = normalizePath $ fromFoldable (S.split (S.Pattern "/") s)
  where
    normalizePath ("":xs) = xs
    normalizePath xs = xs

toWaiRequest :: NH.Request -> Request
toWaiRequest req =
  let
    rawPathInfo = NH.requestURL req
    idxparam = S.indexOf (S.Pattern "?") rawPathInfo
    rawQs = flip S.drop rawPathInfo <<< (+) 1 <$> idxparam
    pathInfo = pathSegments $ fromMaybe rawPathInfo (flip S.take rawPathInfo <$> idxparam)
    headers = FO.toUnfoldable (NH.requestHeaders req) :: Array (Tuple String String)
  in
    Request $
      { httpVersion: fromMaybe H.http10 (H.string2HttpVersion $ NH.httpVersion req)
      , method: fromMaybe H.GET (H.string2HTTPMethod $ NH.requestMethod req)
      , rawPathInfo: rawPathInfo
      , rawQueryString: fromMaybe "" rawQs
      , query: rawQs >>= parsedQuery
      , pathInfo: pathInfo
      , headers: H.fromHeaders headers
      , body: NH.requestAsStream req
      }
