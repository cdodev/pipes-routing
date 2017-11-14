{-# LANGUAGE AllowAmbiguousTypes        #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE FunctionalDependencies     #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE PolyKinds                  #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# OPTIONS_GHC -Wall #-}
module Pipes.Routing.Ingest (
    ZMQRouter, rSettings, router
  , makeZMQRouter
  , runRouter
  , retagRouter
  , IngestSettings(..)
  , HasIngestSettings(..)
  , ZMQIngester(client, IngestNodeT, IngestClientT)
  , IngestNode
  , IngestClient
  , makeIngester
  ) where

import           Control.Concurrent       (threadDelay)
import           Control.Concurrent.Async (Async)
import           Control.Lens             (makeClassy, (^.))
import           Control.Monad.IO.Class   (MonadIO, liftIO)
import           Data.Serialize           (Serialize)
import           Pipes                    (Consumer, Producer)
import           System.ZMQ4.Monadic      as ZMQ

import           Pipes.Routing.Types
import           Pipes.Routing.ZMQ        (sockPublisher, sockSubscriber)


--------------------------------------------------------------------------------
data IngestSettings = IngestSettings {
    _sendTo   :: String -- XSub bound to this address
  , _recvFrom :: String -- XPub bound to this address
  }

makeClassy ''IngestSettings

--------------------------------------------------------------------------------
data ZMQRouter r = ZMQRouter {
    _rSettings :: IngestSettings
  , _router    :: Async ()
  }


makeClassy ''ZMQRouter

instance HasIngestSettings (ZMQRouter r) where
  ingestSettings = rSettings

makeZMQRouter :: IngestSettings -> ZMQ z (ZMQRouter ())
makeZMQRouter ingestPorts = ZMQRouter ingestPorts <$> mkRouter
  where
    mkRouter = ZMQ.async $ do
      pub <- ZMQ.socket XPub
      ZMQ.bind pub (ingestPorts ^. recvFrom)
      sub <- ZMQ.socket XSub
      ZMQ.bind sub (ingestPorts ^. sendTo)
      ZMQ.proxy sub pub Nothing
      liftIO $ threadDelay 10000

runRouter :: MonadIO m => IngestSettings -> m (ZMQRouter ())
runRouter is = ZMQ.runZMQ $ makeZMQRouter is

retagRouter :: ZMQRouter a -> ZMQRouter b
retagRouter (ZMQRouter s r) = ZMQRouter s r
--------------------------------------------------------------------------------
-- LOW LEVEL SOCKET OPS

--------------------------------------------------------------------------------
class ZMQIngester api where
  type IngestClientT api (m :: * -> *) :: *
  type IngestNodeT api (m :: * -> *) :: *
  zmqIngester :: Proxy api -> (ZMQRouter r) -> ZMQ z (IngestNode api z)
  client :: ZMQRouter api -> ZMQ z (IngestClient api z)

type IngestNode api z = IngestNodeT api (ZMQ z)
type IngestClient api z = IngestClientT api (ZMQ z)

instance (Typeable a, Serialize a, KnownSymbol name , api ~ (name ::: (a :: *)))
  => ZMQIngester (name ::: a) where

  type IngestClientT (name ::: a) (m :: * -> *) = Consumer a m ()

  type IngestNodeT (name ::: a) (m :: * -> *) = Producer a m ()

  zmqIngester pChan@(Proxy :: Proxy (name ::: a)) zmqRouter = do
    let s = zmqRouter ^. rSettings.recvFrom
    liftIO . putStrLn $ "Connecting " ++ symbolVal (Proxy :: Proxy name)
    sock <- ZMQ.socket Sub -- ZMQ.async (go s)
    -- ZMQ.subscribe sock (nodeChannel (Proxy :: Proxy name) ^. packedChars)
    ZMQ.connect sock s
    return $ sockSubscriber sock pChan

  client zmqRouter = do
    let s = zmqRouter ^. sendTo
    sock <- ZMQ.socket Pub -- ZMQ.async (go s)
    ZMQ.connect sock s
    return $ sockPublisher sock pApi
    where pApi = Proxy :: Proxy api

instance (ZMQIngester a, ZMQIngester b) => ZMQIngester (a :<|> b) where
  type IngestClientT (a :<|> b) m = IngestClientT a m :<|> IngestClientT b m
  type IngestNodeT (a :<|> b) m = IngestNodeT a m :<|> IngestNodeT b m
  zmqIngester (Proxy :: Proxy (a :<|> b)) zmqRouter = do
    ta <- za
    tb <- zb
    return $ ta :<|> tb
    where
      za = zmqIngester (Proxy :: Proxy a) zmqRouter
      zb = zmqIngester (Proxy :: Proxy b) zmqRouter
  client (zmqRouter :: ZMQRouter (a :<|> b)) = do
    ca <- client (retagRouter zmqRouter :: ZMQRouter a)
    cb <- client (retagRouter zmqRouter :: ZMQRouter b)
    return (ca :<|> cb)


--------------------------------------------------------------------------------
makeIngester
  :: (ZMQIngester api)
  => Proxy api
  -> ZMQRouter r
  -> ZMQ z (ZMQRouter (CombineApis r api), IngestNodeT api (ZMQ z))
makeIngester pApi zmqRouter = (retagRouter zmqRouter,) <$> zmqIngester pApi zmqRouter


-- mkClient
--   :: (ZMQIngester api)
--   => ZMQRouter api
--   -> ZMQ z (ZMQRouter b, IngestClientT api (ZMQ z))
-- mkClient zmqRouter = client zmqRouter
-- unpack :: Network api -> IO a
-- unpack (NetworkLeaf n) = n
-- unpack (NetworkAlt (a :<|> b)) = do
--   l <- unpack a
--   _

--------------------------------------------------------------------------------
-- connectNode
--   :: (MonadReader r m, MonadIO m, HasIngestSettings r, Serialize a, KnownSymbol chan)
--   => Node chan a -> m (Async ())
-- connectNode n = do
--   s <- view sendTo
--   liftIO . putStrLn $ "Connecting " ++ nodeChannel n
--   ZMQ.runZMQ $ do
--     sock <- ZMQ.socket Pub -- ZMQ.async (go s)
--     ZMQ.connect sock s
--     ZMQ.async (go sock)
--   where
--   chan' = view packedChars $ nodeChannel n
--   go :: Socket z Pub -> ZMQ z ()
--   go s = do
--     msg <- liftIO $ atomically $ recv (n ^. nodeOut)
--     case msg of
--       Just m -> do
--         -- liftIO $ print (chan', encode m)
--         ZMQ.sendMulti s $ chan' :| [encode m]
--         go s
--       Nothing -> liftIO . putStrLn $ (nodeChannel n) ++ " got nothing"

--------------------------------------------------------------------------------
-- runIngester
--   :: (ZMQIngester api, MonadIO m, HasIngestSettings r, MonadReader r m)
--   => Network api -> m (Async ())
-- runIngester n = do
--   (subAddr, pubAddr) <- (,) <$> view sendTo <*> view recvFrom
--   liftIO $ print (subAddr, pubAddr)
--   proxy <- ZMQ.runZMQ $ ZMQ.async $ do
--     pub <- ZMQ.socket XPub
--     ZMQ.bind pub pubAddr
--     sub <- ZMQ.socket XSub
--     ZMQ.bind sub subAddr
--     ZMQ.proxy sub pub Nothing
--   liftIO $ threadDelay 10000
--   ing <- zmqIngester n
--   liftIO (Async.async (const () <$> Async.waitBoth proxy ing))
