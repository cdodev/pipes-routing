{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE PolyKinds                  #-}
{-# LANGUAGE QuasiQuotes                #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# OPTIONS_GHC -Wall #-}

module Pipes.Routing
  -- ( EventScans(..)
  -- , sn
  -- , Sock
  -- , runSock
  -- )
  where

import Control.Lens
import           Data.Serialize       (Serialize, encode, decode)
import           Data.Typeable        (Typeable)
import Data.Proxy
import           Control.Monad.Reader
import           Control.Concurrent
import           Control.Concurrent.Async
import           GHC.Generics
import           Servant
import qualified System.ZMQ4.Monadic      as ZMQ

import           Pipes.Routing.Ingest
import           Pipes.Routing.Network

data AThing = AThing Double Double deriving (Generic, Typeable, Serialize, Show)

type TestAPI =
       "int" :> Int
  :<|> "str" :> String
  :<|> "thing" :> AThing

testApi :: Proxy TestAPI
testApi = Proxy

ingSettings = IngestSettings "ipc:///tmp/send" "ipc:///tmp/recv"

main :: IO ()
main = do
  net <- networkNode testApi
  ing <- flip runReaderT ingSettings $ runIngester net
  putStrLn "Created ingester"
  -- threadDelay 1000000
  sendInt :<|> sendStr :<|> sendThing <- client net
  putStrLn "Created clients"
  a <- ZMQ.runZMQ $ do
    s <- ZMQ.socket ZMQ.Sub
    ZMQ.connect s (ingSettings ^. recvFrom)
    ZMQ.subscribe s ""
    liftIO $ putStrLn "subscribed"
    ZMQ.async $ forever $ do
      [chan, bs] <- ZMQ.receiveMulti s
      -- msg <- ZMQ.receive s
      liftIO $ print (chan, decode bs :: Either String AThing)
      liftIO $ putStrLn "====================="
      liftIO (threadDelay 1000000)
  threadDelay 10000
  putStrLn "Sending"
  sendInt 1
  sendInt 2
  sendStr "test"
  void $ sendThing (AThing 1.1 2.2)
  void $ sendThing (AThing 5.1 5.2)
  void $ wait a
