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
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# OPTIONS_GHC -Wall #-}
module Pipes.Routing.Ingest where

import           Control.Concurrent.Async (Async)
import           Control.Concurrent
import qualified Control.Concurrent.Async as Async
import           Control.Lens
import           Control.Monad.IO.Class   (MonadIO, liftIO)
import           Control.Monad.Reader
import           Data.ByteString.Lens
import           Data.IORef
import           Data.List.NonEmpty       (NonEmpty (..))
import           Data.Serialize           (Serialize, encode)
import           Data.Typeable            (Typeable)
import           GHC.TypeLits
import           Pipes.Concurrent
import           Servant
import           System.ZMQ4.Monadic      (Pub (Pub), Socket, XPub (XPub),
                                           XSub (XSub), ZMQ)
import qualified System.ZMQ4.Monadic      as ZMQ


import           Pipes.Routing.Network


--------------------------------------------------------------------------------
data IngestSettings = IngestSettings {
    _sendTo   :: String -- XSub bound to this address
  , _recvFrom :: String -- XPub bound to this address
  }

makeClassy ''IngestSettings

--------------------------------------------------------------------------------
class HasNetwork api => ZMQIngester api where
  type IngestClient api :: *
  zmqIngester :: (MonadReader r m, MonadIO m, HasIngestSettings r) => Network api -> m (Async ())
  client :: Network api -> IO (IngestClient api)

-- type IngestClient api = IngestClientT api IO

instance (Typeable a, Serialize a, KnownSymbol name
         , HasNetwork api, api ~ (name :> (a :: *)))
  => ZMQIngester (name :> a) where
  type IngestClient (name :> a) = a -> IO Bool
  zmqIngester (NetworkLeaf n) = connectNode =<< (liftIO $ readIORef n)
  client (NetworkLeaf n) = do
    node <- readIORef n
    putStrLn $ "Creating node " ++ nodeChannel node
    return (sendNode node)

instance (ZMQIngester a, ZMQIngester b) => ZMQIngester (a :<|> b) where
  type IngestClient (a :<|> b) = IngestClient a :<|> IngestClient b
  zmqIngester (NetworkAlt (a :<|> b)) = do
    ta <- za
    tb <- zb
    liftIO (Async.async (const () <$> Async.waitBoth ta tb))
    where
      za = zmqIngester a
      zb = zmqIngester b
  client (NetworkAlt (a :<|> b)) = do
    ca <- client a
    cb <- client b
    return (ca :<|> cb)

-- unpack :: Network api -> IO a
-- unpack (NetworkLeaf n) = n
-- unpack (NetworkAlt (a :<|> b)) = do
--   l <- unpack a
--   _

--------------------------------------------------------------------------------
connectNode
  :: (MonadReader r m, MonadIO m, HasIngestSettings r, Serialize a, KnownSymbol chan)
  => Node chan a -> m (Async ())
connectNode n = do
  s <- view sendTo
  liftIO . putStrLn $ "Connecting " ++ nodeChannel n
  ZMQ.runZMQ $ do
    sock <- ZMQ.socket Pub -- ZMQ.async (go s)
    ZMQ.connect sock s
    ZMQ.async (go sock)
  where
  chan' = view packedChars $ nodeChannel n
  go :: Socket z Pub -> ZMQ z ()
  go s = do
    msg <- liftIO $ atomically $ recv (n ^. nodeOut)
    case msg of
      Just m -> do
        -- liftIO $ print (chan', encode m)
        ZMQ.sendMulti s $ chan' :| [encode m]
        go s
      Nothing -> liftIO . putStrLn $ (nodeChannel n) ++ " got nothing"

--------------------------------------------------------------------------------
runIngester
  :: (ZMQIngester api, MonadIO m, HasIngestSettings r, MonadReader r m)
  => Network api -> m (Async ())
runIngester n = do
  (subAddr, pubAddr) <- (,) <$> view sendTo <*> view recvFrom
  liftIO $ print (subAddr, pubAddr)
  proxy <- ZMQ.runZMQ $ ZMQ.async $ do
    pub <- ZMQ.socket XPub
    ZMQ.bind pub pubAddr
    sub <- ZMQ.socket XSub
    ZMQ.bind sub subAddr
    ZMQ.proxy sub pub Nothing
  liftIO $ threadDelay 100000
  ing <- zmqIngester n
  liftIO (Async.async (const () <$> Async.waitBoth proxy ing))
