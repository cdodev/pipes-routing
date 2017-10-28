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
import           Pipes.Concurrent
import           Servant
import           System.ZMQ4.Monadic      (Socket, XPub, ZMQ)
import qualified System.ZMQ4.Monadic      as ZMQ

newtype PubState s z a =
  PubState { unPubState :: StateT s (ZMQ z) a }
  deriving (Functor, Applicative, Monad, MonadIO, MonadState s)


runPubState :: s -> PubState s z a -> ZMQ z a
runPubState s = flip evalStateT s . unPubState

-- class HasNetwork api => ZMQPublisher api where
--   zmqPublisher :: Network api -> PubState (Socket z XPub) z (Async ())

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
