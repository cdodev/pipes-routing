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
import qualified Control.Concurrent.Async as Async
import           Control.Lens
import           Control.Monad.IO.Class   (MonadIO, liftIO)
import           Control.Monad.Reader
import Data.ByteString.Lens 
import Data.List.NonEmpty (NonEmpty (..))
import           Data.Serialize           (Serialize, encode)
import           Data.Typeable            (Typeable)
import           GHC.TypeLits
import           Pipes.Concurrent
import           Servant
import           System.ZMQ4.Monadic      (Pub (Pub), Socket, XPub (XPub),
                                           XSub (XSub), ZMQ)
import qualified System.ZMQ4.Monadic      as ZMQ


import           Pipes.Routing.Network


data IngestSettings = IngestSettings {
    _sendTo   :: String -- XSub bound to this address
  , _recvFrom :: String -- XPub bound to this address
  }

makeClassy ''IngestSettings


class HasNetwork api => ZMQIngester api where
  zmqIngester :: (MonadReader r m, MonadIO m, HasIngestSettings r) => Network api -> m (Async ())

instance (Typeable a, Serialize a, KnownSymbol name
         , HasNetwork api, api ~ (name :> (a :: *)))
  => ZMQIngester api where
  zmqIngester (NetworkLeaf n) = connectNode =<< liftIO n

instance (ZMQIngester a, ZMQIngester b) => ZMQIngester (a :<|> b) where
  zmqIngester (NetworkAlt (a :<|> b)) = do
    ta <- za
    tb <- zb
    liftIO (Async.async (const () <$> Async.waitBoth ta tb))
    where
      za = zmqIngester a
      zb = zmqIngester b

connectNode
  :: (MonadReader r m, MonadIO m, HasIngestSettings r, Serialize a, KnownSymbol chan)
  => Node chan a -> m (Async ())
connectNode n = do
  s <- view sendTo
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
        ZMQ.sendMulti s $ chan' :| [encode m]
        go s
      Nothing -> return ()

runPublisher
  :: (ZMQIngester api, MonadIO m, HasIngestSettings r, MonadReader r m)
  => Network api -> m ()
runPublisher n = do
  (subAddr, pubAddr) <- (,) <$> view sendTo <*> view recvFrom
  ZMQ.runZMQ $ do
    pub <- ZMQ.socket XPub
    ZMQ.bind pub pubAddr
    sub <- ZMQ.socket XSub
    ZMQ.bind sub subAddr
    ZMQ.proxy sub pub Nothing
  a <- zmqIngester n
  liftIO $ Async.wait a
