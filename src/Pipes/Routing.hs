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
import           Data.Serialize           (Serialize)
import           Data.Typeable            (Typeable)
import           GHC.Generics
import qualified System.ZMQ4.Monadic      as ZMQ
import Pipes ((>->), runEffect, Producer, Consumer)
import qualified Pipes as P
import qualified Pipes.Prelude as P

import           Pipes.Routing.Types
import           Pipes.Routing.Ingest
import           Pipes.Routing.Process
import           Pipes.Routing.Publish

data AThing = AThing Double Double deriving (Generic, Typeable, Serialize, Show)

type TestAPI =
       "int" ::: Int
  :<|> "str" ::: String
  :<|> "thing" ::: AThing
  :<|> "print" ::: String

type TestProcess =
       (("int" :<+> "str") :-> "either-int-string" ::: Either Int String)
  :<|> ("int" :-> "tuple-ints" ::: (Int, Int))

testApi :: Proxy TestAPI
testApi = Proxy

ingSettings :: IngestSettings
ingSettings = IngestSettings "ipc:///tmp/rsend" "ipc:///tmp/rrecv"

data Eis = Eis {
    int :: Int -> Either Int String
  , str:: String -> Either Int String
  } deriving (Generic)

eis :: Joiner '["int" ::: Int, "str" ::: String] (Either Int String)
eis  = Joiner (Eis Left Right)

eisN :: JoinerT TestAPI (("int" :<+> "str") :-> "either-int-string" ::: Either Int String)
eisN = Node eis

iajN :: JoinerT TestAPI ("int" :-> "tuple-ints" ::: (Int, Int))
iajN = Node iaj

testJoiner :: JoinerT TestAPI TestProcess
testJoiner = Alt (eisN :<|> iajN)

sendToPrint
  :: (Show a, Monad m) => String -> Consumer String m () -> Producer a m () -> m ()
sendToPrint label prnt prod = P.runEffect $ prod >-> P.map ((\s -> label ++ " -- " ++ s) . show) >-> prnt

main :: IO ()
main = do
  -- a <- ZMQ.runZMQ $ do
  r <- ZMQ.runZMQ $ do
    r' <- makeZMQRouter ingSettings
    liftIO $ putStrLn "made router"
    (ri, _ingester) <- makeIngester testApi r'
    liftIO $ putStrLn "made ingester"
    -- liftIO (runAlt ing)
    liftIO (threadDelay 10000)
    -- sendInt :<|> sendStr :<|> sendThing <- client ri
    liftIO $ putStrLn "made client"
    liftIO (threadDelay 10000)
    (rp, eisProc :<|> iiProc )<- runProcessor ri testJoiner
    (sendInt :<|> sendStr :<|> sendThing :<|> printChan :<|> sendEitherIS :<|> _x)  <- client rp
    liftIO $ putStrLn "subscribed"
    liftIO (threadDelay 80000)

    void $ ZMQ.async $ do
      liftIO $ putStrLn "un-paused"
      runEffect (P.each [1..5] >-> sendInt)
      liftIO (threadDelay 1000)
      runEffect (P.each ["test", "test2"] >-> sendStr)
      liftIO (threadDelay 1000)
      runEffect (P.each  [AThing 1.1 2.2, AThing 5.1 5.2] >-> sendThing)
      liftIO (threadDelay 1000)
      runEffect (P.each [10..15] >-> sendInt)
      liftIO (threadDelay 10000)
      void $ ZMQ.async $ sendToPrint "eis" printChan eisProc  --runEffect $ eisProc >-> P.print
      void $ ZMQ.async $ sendToPrint "eis" printChan iiProc  --runEffect $ eisProc >-> P.print
      -- liftIO (threadDelay 10000)
      -- ZMQ.async $ forever $ do
      --   [chan, bs] <- ZMQ.receiveMulti s
      --   -- msg <- ZMQ.receive s
      --   liftIO $ print (chan, decode bs :: Either String (Either Int String))
      --   liftIO $ putStrLn "====================="
      --   liftIO (threadDelay 1000)
    -- liftIO (threadDelay 10000)
    -- runEffect $ iiProc >-> P.print
    runEffect (P.each [Right "XXXX", Right "ZZZZZ", Left 11111111] >-> sendEitherIS)
    return rp

  ZMQ.runZMQ $ do
    sendPrnt <- client (retagRouter r :: ZMQRouter ("print" ::: String))
    prnt <- getPublisher r (Proxy :: Proxy "print")
    strPub <- getPublisher r (Proxy :: Proxy "str")
    intPub <- getPublisher r (Proxy :: Proxy "int")
    void $ ZMQ.async $ sendToPrint "str" sendPrnt strPub
    void $ ZMQ.async $ sendToPrint "int" sendPrnt intPub
    runEffect $ prnt >-> P.stdoutLn
  -- void $ sendThing (AThing 1.1 2.2)
  -- void $ sendThing (AThing 5.1 5.2)
  void $ wait (r ^. router)
