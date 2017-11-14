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
module Pipes.Routing.Publish (
    ZMQPublisher(..)
  , Publisher
  ) where

import           Control.Lens         ((^.))
import           Data.Serialize       (Serialize)
import           Pipes                (Producer)
import           System.ZMQ4.Monadic  (Sub (Sub), ZMQ)
import qualified System.ZMQ4.Monadic  as ZMQ

import           Pipes.Routing.Ingest
import           Pipes.Routing.Types
import           Pipes.Routing.ZMQ

class ZMQPublisher api (chan :: k) where
  type PublisherT api chan (m :: * -> *) :: *
  getPublisher
    :: ZMQRouter api
    -> Proxy chan
    -> ZMQ z (Publisher api chan z)

type Publisher api chan z = PublisherT api chan (ZMQ z)

instance (ChannelType chan api ~ out, Serialize out, KnownSymbol chan) => ZMQPublisher api chan where
  type PublisherT api chan m = Producer (ChannelType chan api) m ()
  getPublisher zmqRouter _pChan = do
    sock <- ZMQ.socket Sub
    ZMQ.connect sock (zmqRouter ^. recvFrom)
    return $ sockSubscriber sock pApi
    where
    pApi = Proxy :: Proxy (chan ::: ChannelType chan api)

instance (ZMQPublisher api l, ZMQPublisher api r) => ZMQPublisher api (l :<|> r) where
  type PublisherT api (l :<|> r) m = PublisherT api l m :<|> PublisherT api r m
  getPublisher zmqRouter _pChan = do
    pl <- getPublisher zmqRouter pL
    pr <- getPublisher zmqRouter pR
    return $ pl :<|> pr
    where
      pL = Proxy :: Proxy l
      pR = Proxy :: Proxy r

