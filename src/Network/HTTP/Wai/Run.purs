module Network.HTTP.Wai.Run
  ( handleRequest
  , module Exports
  ) where

import Prelude

import Data.Either (Either(..))
import Effect (Effect)
import Effect.Aff (Aff, runAff_)
import Effect.Exception (throwException)

import Node.HTTP as NH

import Network.HTTP.Wai (Application, toWaiRequest, reqHeaders)
import Network.HTTP.Wai (Application, Middleware) as Exports
import Network.HTTP.Wai.Header (keyedRequestHeader)
import Network.HTTP.Wai.Response (sendResponse)
import Network.HTTP.Wai.Internal (ResponseReceived(..))

handleRequest :: Application -> NH.Request -> NH.Response -> Effect Unit
handleRequest app req res = do
  let wreq   = toWaiRequest req
      hmap   = keyedRequestHeader $ reqHeaders wreq
      sender wres = do
        handleAff (sendResponse res wreq hmap wres) -- TODO is this a proper replacement for handleAff below
        pure ResponseReceived
  _ <- app wreq sender
  pure unit

handleAff :: forall a. Aff a -> Effect Unit
handleAff = runAff_ $ case _ of
  Left e -> throwException e
  Right _ -> pure unit

-- handleAff :: forall a. Aff a -> Effect Unit
-- handleAff = void <<< runAff throwException (const (pure unit))
