{-# LANGUAGE AllowAmbiguousTypes        #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE PolyKinds                  #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# OPTIONS_GHC -Wall #-}
module Pipes.Routing.Publish where

import           Control.Concurrent.Async (Async)
import qualified Control.Concurrent.Async as Async
import           Control.Lens
import           Control.Monad.Except
import           Control.Monad.IO.Class   (MonadIO, liftIO)
import           Control.Monad.State      (MonadState, StateT (..), evalStateT,
                                           get)
import           Data.Serialize           (Serialize, encode)
import           Data.Typeable            (Typeable)
import           GHC.TypeLits
import           Pipes (Producer)
import           Servant
import           System.ZMQ4.Monadic      (Socket, XPub, ZMQ, Sub(Sub))
import qualified System.ZMQ4.Monadic      as ZMQ

import Pipes.Routing.Types
import Pipes.Routing.Ingest

class ZMQPublisher api (chan :: k) where
  type PublisherT api chan (m :: * -> *) :: *
  getPublisher
    :: IngestSettings
    -> Proxy api
    -> Proxy chan
    -> ZMQ z (Publisher api chan z)

type Publisher api chan z = PublisherT api chan (ZMQ z)

instance (ChannelType chan api ~ out, Serialize out, KnownSymbol chan) => ZMQPublisher api chan where
  type PublisherT api chan m = Producer (ChannelType chan api) m ()
  getPublisher s _pApi _pChan = do
    sock <- ZMQ.socket Sub
    ZMQ.connect sock (s ^. recvFrom)
    return $ sockSubscriber sock pApi
    where
    pApi = Proxy :: Proxy (chan ::: ChannelType chan api)

instance (ZMQPublisher api l, ZMQPublisher api r) => ZMQPublisher api (l :<|> r) where
  type PublisherT api (l :<|> r) m = PublisherT api l m :<|> PublisherT api r m
  getPublisher s pApi _pChan = do
    pl <- getPublisher s pApi pL
    pr <- getPublisher s pApi pR
    return $ pl :<|> pr
    where
      pL = Proxy :: Proxy l
      pR = Proxy :: Proxy r


-- instance (Typeable a, Serialize a, KnownSymbol name
--          , HasNetwork api, api ~ (name ::: (a :: *)))
--   => ZMQPublisher api where
--   zmqPublisher (NetworkLeaf n) = do
--     s <- get
--     (node :: Node name a) <- liftIO n
--     PubState . lift $ connectNode s node

-- instance (ZMQPublisher a, ZMQPublisher b) => ZMQPublisher (a :<|> b) where
--   zmqPublisher (NetworkAlt (a :<|> b)) = do
--     ta <- za
--     tb <- zb
--     liftIO (Async.async (const () <$> Async.waitBoth ta tb))
--     where
--       za = zmqPublisher a
--       zb = zmqPublisher b

-- connectNode :: Serialize a => Socket z XPub -> Node chan a -> ZMQ z (Async ())
-- connectNode s n = ZMQ.async go
--   where
--   go = do
--     msg <- liftIO $ atomically $ recv (n ^. nodeOut)
--     case msg of
--       Just m -> do
--         ZMQ.send s [] $ encode m
--         go
--       Nothing -> return ()

-- runPublisher :: (ZMQPublisher api, MonadIO m) => Network api -> m ()
-- runPublisher n =  ZMQ.runZMQ $ do
--   s <- ZMQ.socket ZMQ.XPub
--   a <- runPubState s (zmqPublisher n)
--   liftIO $ Async.wait a
