{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DeriveGeneric              #-}
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

import           Control.Concurrent
import           Control.Concurrent.Async
import           Control.Lens
import           Control.Monad.Reader
import           Data.Proxy
import           Data.Serialize           (Serialize, decode, encode)
import           Data.Typeable            (Typeable)
import           GHC.Generics
import qualified System.ZMQ4.Monadic      as ZMQ
import Pipes ((>->), runEffect)
import qualified Pipes as P
import qualified Pipes.Prelude as P

import           Pipes.Routing.Types
import           Pipes.Routing.Ingest
import           Pipes.Routing.Process

data AThing = AThing Double Double deriving (Generic, Typeable, Serialize, Show)

type TestAPI =
       "int" ::: Int
  :<|> "str" ::: String
  :<|> "thing" ::: AThing

type TestProcess =
       ("int" :<+> "str") :-> "either-int-string" ::: Either Int String
  :<|> "int" :-> "int-adder" ::: (Int, Int)

testApi :: Proxy TestAPI
testApi = Proxy

ingSettings :: IngestSettings
ingSettings = IngestSettings "inproc://send" "inproc://recv"

data Eis = Eis {
    int :: Int -> Either Int String
  , str:: String -> Either Int String
  } deriving (Generic)

eis :: Joiner '["int" ::: Int, "str" ::: String] (Either Int String) Eis
eis  = Joiner (Eis Left Right)

testJoiner :: JoinerT TestAPI TestProcess j
testJoiner = Alt (eis :<|> iaj)

main :: IO ()
main = do
  r <- ZMQ.runZMQ $ do
    r' <- makeZMQRouter ingSettings
    liftIO $ putStrLn "made router"
    i :<|> str :<|> th <- zmqIngester testApi ingSettings
    liftIO $ putStrLn "made ingester"
    -- liftIO (runAlt ing)
    liftIO (threadDelay 10000)
    sendInt :<|> sendStr :<|> sendThing <- client testApi ingSettings
    liftIO $ putStrLn "made client"
    liftIO (threadDelay 10000)
    eisProc :<|> iiProc <- process ingSettings testApi eis
    ZMQ.async $ runEffect (i >-> P.map ("int",) >-> P.print)
    ZMQ.async $ runEffect (str >-> P.map ("str: " ++) >-> P.stdoutLn)
    ZMQ.async $ runEffect (th >-> P.print)
    runEffect (P.each [1..5] >-> sendInt)
    liftIO (threadDelay 1000)
    runEffect (P.each ["test", "test2"] >-> sendStr)
    liftIO (threadDelay 1000)
    runEffect (P.each  [AThing 1.1 2.2, AThing 5.1 5.2] >-> sendThing)
    liftIO (threadDelay 1000)
    runEffect (P.each [10..15] >-> sendInt)
    liftIO (threadDelay 10000)
    runEffect $ eisProc >-> P.print
    return r'
  -- a <- ZMQ.runZMQ $ do
  --   s <- ZMQ.socket ZMQ.Sub
  --   ZMQ.connect s (ingSettings ^. recvFrom)
  --   ZMQ.subscribe s ""
  --   liftIO $ putStrLn "subscribed"
  --   ZMQ.async $ forever $ do
  --     [chan, bs] <- ZMQ.receiveMulti s
  --     -- msg <- ZMQ.receive s
  --     liftIO $ print (chan, decode bs :: Either String AThing)
  --     liftIO $ putStrLn "====================="
  --     liftIO (threadDelay 1000)
  -- void $ sendThing (AThing 1.1 2.2)
  -- void $ sendThing (AThing 5.1 5.2)
  void $ wait (r ^. router)
