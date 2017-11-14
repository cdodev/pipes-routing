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
module Pipes.Routing.ZMQ (
    sockSubscriber
  , sockPublisher
  , sockPuller
  , sockPusher
  , nodeChannel
  , subChannel
  ) where

import           Control.Lens
import           Control.Monad        (forever)
import           Data.ByteString      (ByteString)
import           Data.ByteString.Lens (packedChars)
import           Data.List.NonEmpty   (NonEmpty (..))
import           Data.Serialize       (Serialize, decode, encode)
import           Pipes                (Consumer, Producer, await, lift, yield)
import           System.ZMQ4.Monadic  as ZMQ

import           Pipes.Routing.Types

--------------------------------------------------------------------------------
sockSubscriber
  :: (KnownSymbol chan, Serialize a)
  => Socket z Sub
  -> Proxy (chan ::: a)
  -> Producer a (ZMQ z) ()
sockSubscriber sub p = do
  lift $ ZMQ.subscribe sub subChan
  forever $ do
    [_chan, bs] <- lift $ ZMQ.receiveMulti sub
    -- liftIO $ print (chan, bs)
    yield (bs ^?! to decode . _Right)
  where
    subChan = subChannel $ chanP p

sockPublisher
  :: (Serialize a, KnownSymbol chan)
  => Socket z Pub -> Proxy (chan ::: a) -> Consumer a (ZMQ z) ()
sockPublisher pub p = forever $ do
  a <- await
  -- liftIO $ putStrLn ("Sending a " ++ (nodeChannel pC))
  lift $ ZMQ.sendMulti pub $ chan' :| [encode a]
  where
    chan' = subChannel $ chanP p

--------------------------------------------------------------------------------
sockPuller
  :: (KnownSymbol chan, Serialize a)
  => Proxy (chan ::: a)
  -> Socket z Pull
  -> Producer a (ZMQ z) ()
sockPuller _ pull = do
  forever $ do
    bs <- lift $ ZMQ.receive pull
    yield (bs ^?! to decode . _Right)

sockPusher :: (Serialize a) => Socket z Push -> Consumer a (ZMQ z) ()
sockPusher push = forever $ do
  a <- await
  lift $ ZMQ.send push [] $ encode a

--------------------------------------------------------------------------------
nodeChannel :: (KnownSymbol chan) => Proxy chan -> String
nodeChannel = symbolVal

subChannel :: (KnownSymbol chan) => Proxy chan -> ByteString
subChannel = view packedChars . nodeChannel
