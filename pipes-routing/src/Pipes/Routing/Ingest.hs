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
module Pipes.Routing.Ingest where

import           Control.Concurrent (threadDelay)
import           Control.Concurrent.Async (Async)
import qualified Control.Concurrent.Async as Async
import           Control.Lens
import           Control.Monad.IO.Class   (MonadIO, liftIO)
import           Control.Monad.Reader
import           Data.ByteString (ByteString)
import           Data.ByteString.Lens
import           Data.IORef
import           Data.List.NonEmpty       (NonEmpty (..))
import           Data.Serialize           (Serialize, encode, decode)
import           Data.Typeable            (Typeable)
import           GHC.TypeLits
import           Pipes                    (Producer, Consumer, await, yield)
import           Servant
import           System.ZMQ4.Monadic      (Pub (Pub), Socket, Sub (Sub),
                                           XPub (XPub), XSub (XSub), ZMQ)
import qualified System.ZMQ4.Monadic      as ZMQ


-- import           Pipes.Routing.Network


--------------------------------------------------------------------------------
data IngestSettings = IngestSettings {
    _sendTo   :: String -- XSub bound to this address
  , _recvFrom :: String -- XPub bound to this address
  }

makeClassy ''IngestSettings

--------------------------------------------------------------------------------
data ZMQRouter = ZMQRouter {
    _ports  :: IngestSettings
  , _router :: Async ()
  }


makeClassy ''ZMQRouter

instance HasIngestSettings ZMQRouter where
  ingestSettings = ports

makeZMQRouter :: IngestSettings -> ZMQ z ZMQRouter
makeZMQRouter ingestPorts = ZMQRouter ingestPorts <$> mkRouter
  where
    mkRouter = ZMQ.async $ do
      pub <- ZMQ.socket XPub
      ZMQ.bind pub (ingestPorts ^. recvFrom)
      sub <- ZMQ.socket XSub
      ZMQ.bind sub (ingestPorts ^. sendTo)
      ZMQ.proxy sub pub Nothing
      liftIO $ threadDelay 10000

runRouter :: MonadIO m => IngestSettings -> m ZMQRouter
runRouter is = ZMQ.runZMQ $ makeZMQRouter is

--------------------------------------------------------------------------------
-- LOW LEVEL SOCKET OPS
sockProducer :: Serialize a =>  Socket z Sub -> Producer a (ZMQ z) ()
sockProducer sub = forever $ do
  [_chan, bs] <- lift $ ZMQ.receiveMulti sub
  -- liftIO $ print (chan, bs)
  yield (bs ^?! to decode . _Right)

mkProducer
  :: forall chan a z. (KnownSymbol chan, Serialize a)
  => Socket z Sub
  -> Proxy (chan ::: a)
  -> Producer a (ZMQ z) ()
mkProducer sub _ = do
  lift $ ZMQ.subscribe sub subChan
  forever $ do
    [_chan, bs] <- lift $ ZMQ.receiveMulti sub
    -- liftIO $ print (chan, bs)
    yield (bs ^?! to decode . _Right)
  where
    subChan =  (nodeChannel (Proxy :: Proxy chan) ^. packedChars)

sockConsumer :: (Serialize a, KnownSymbol chan) => Socket z Pub -> Proxy chan -> Consumer a (ZMQ z) ()
sockConsumer pub pC = forever $ do
  a <- await
  -- liftIO $ putStrLn ("Sending a " ++ (nodeChannel pC))
  lift $ ZMQ.sendMulti pub $ chan' :| [encode a]
  where
    chan' = nodeChannel pC ^. packedChars

nodeChannel :: forall chan a. (KnownSymbol chan) => Proxy chan -> String
nodeChannel = symbolVal

--------------------------------------------------------------------------------
class ZMQIngester api where
  type IngestClientT api (m :: * -> *) :: *
  type IngestNodeT api (m :: * -> *) :: *
  zmqIngester :: Proxy api -> IngestSettings -> ZMQ z (IngestNode api z)
  client :: Proxy api -> IngestSettings -> ZMQ z (IngestClient api z)

type IngestNode api z = IngestNodeT api (ZMQ z)
type IngestClient api z = IngestClientT api (ZMQ z)

instance (Typeable a, Serialize a, KnownSymbol name , api ~ (name ::: (a :: *)))
  => ZMQIngester (name ::: a) where

  type IngestClientT (name ::: a) (m :: * -> *) = Consumer a m ()

  type IngestNodeT (name ::: a) (m :: * -> *) = Producer a m ()

  zmqIngester pChan@(Proxy :: Proxy (name ::: a)) is = do
    let s = is ^. recvFrom
    liftIO . putStrLn $ "Connecting " ++ symbolVal (Proxy :: Proxy name)
    sock <- ZMQ.socket Sub -- ZMQ.async (go s)
    -- ZMQ.subscribe sock (nodeChannel (Proxy :: Proxy name) ^. packedChars)
    ZMQ.connect sock s
    return $ mkProducer sock pChan

  client (Proxy :: Proxy (name ::: a)) is = do
    let s = is ^. sendTo
    sock <- ZMQ.socket Pub -- ZMQ.async (go s)
    ZMQ.connect sock s
    return $ sockConsumer sock (Proxy :: Proxy name)

instance (ZMQIngester a, ZMQIngester b) => ZMQIngester (a :<|> b) where
  type IngestClientT (a :<|> b) m = IngestClientT a m :<|> IngestClientT b m
  type IngestNodeT (a :<|> b) m = IngestNodeT a m :<|> IngestNodeT b m
  zmqIngester (Proxy :: Proxy (a :<|> b)) is = do
    ta <- za
    tb <- zb
    return $ ta :<|> tb
    where
      za = zmqIngester (Proxy :: Proxy a) is
      zb = zmqIngester (Proxy :: Proxy b) is
  client (Proxy :: Proxy (a :<|> b)) is = do
    ca <- client (Proxy :: Proxy a) is
    cb <- client (Proxy :: Proxy b) is
    return (ca :<|> cb)

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
