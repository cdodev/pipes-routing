{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE DeriveFoldable             #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DeriveTraversable          #-}
{-# LANGUAGE ExistentialQuantification  #-}
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
module Pipes.Routing.Network where

import           Control.Lens
import           Control.Monad.Except
import           Data.Map             (Map)
import qualified Data.Map             as Map
import           Data.Maybe           (fromJust)
import           Data.Proxy
import           Data.Semigroup       (Semigroup (..))
import           Data.Text
import           Data.Text.Lens
import           Data.Typeable        (cast)
import           Data.Typeable        (Typeable)
import           GHC.Generics         (Generic)
import           GHC.TypeLits
import           Pipes                hiding (Proxy)
import qualified Pipes                as P
import           Pipes.Concurrent
import           Servant
import System.ZMQ4.Monadic (ZMQ)
import qualified System.ZMQ4.Monadic as ZMQ
import Control.Monad.IO.Class (liftIO, MonadIO)

import Pipes.Routing.Types
import Pipes.Routing.HMap
import Pipes.Routing.Operations hiding (return, (=<<), (>>=), (>>))


newtype Sock a =
  Sock { unSock :: Output a } deriving (Generic)

makeWrapped ''Sock

-- instance Functor m => Functor (Sock m) where
--   fmap f = Sock . fmap f . unSock
-- instance Applicative m => Applicative (Sock m)
-- instance Monad m => Monad (Sock m)
-- instance MonadIO m => MonadIO (Sock m)

mkSock
  :: (Show a, MonadIO m, KnownSymbol chan, ChannelType chan api ~ a)
  => Proxy api -> Proxy chan -> m (Input a, Sock a)
mkSock _ pChan = do
  (o, i, _c) <- liftIO $ spawn' unbounded
  return (i, Sock o)
  where chanName = symbolVal pChan

runSock :: Sock a -> a -> STM Bool
runSock (Sock o) = send o

---------------------------------------------------------------------------------


data Err deriving Generic

-- instance Error Err
-- runChans :: (IxMonadState m, MonadIO (m i i)) => Proxy routes -> m i j a
-- runChans pRoutes = do
--   liftIO $ mkChannels pRoutes

--------------------------------------------------------------------------------
data Node (chan :: Symbol) a = Node {
    _nodeIn :: Output a
  , _nodeOut :: Input a
  , _nodeSeal :: STM ()
  } deriving (Generic)

makeLenses ''Node

mkNode :: Buffer a -> IO (Node chan a)
mkNode x = do
  (o, i, s) <- spawn' x
  return $ Node o i s

--------------------------------------------------------------------------------
class HasNetwork api where
  type NetworkT api (m :: * -> *) :: *
  networkNode :: Proxy api -> Network api


type Network api = NetworkT api IO --(RouteBuild api r)
-- type Network api i = NetworkT api (ExceptT Err IO)

data Debug

type family PublishChannels processor :: * where
  PublishChannels (a :<|> b) = (PublishChannels a) :<|> (PublishChannels b)
  PublishChannels (a :-> b) = b


instance (HasNetwork a , HasNetwork b ) => HasNetwork (a :<|> b) where
  type NetworkT (a :<|> b) m = NetworkT a m :<|> NetworkT b m
  --   RouteBuild (a :<|> b) r (IxOutput (NetworkT (Chans b r) a m) :<|> IxOutput (NetworkT r b m))
  networkNode (Proxy :: Proxy (a :<|> b)) =
    networkNode pA :<|> networkNode pB
      where
        pA = Proxy :: Proxy a
        pB = Proxy :: Proxy b

instance (Typeable a, Channels (name :> a), KnownSymbol name, Show a) => HasNetwork (name :> a) where
  type NetworkT (name :> a) (m :: * -> *) = IO (Node name a)
  networkNode _pApi = mkNode unbounded

processorPublishClient
  :: forall api pub. (HasNetwork api, (PublishChannels pub ~ api))
  => Proxy pub -> Network api
processorPublishClient (Proxy :: Proxy pub) = networkNode pApi
  where pApi = Proxy :: Proxy api


zmqPublisher :: (HasNetwork api) => Network api -> 
-- class PublishClient a where
--   type Client a :: *
--   type RouteState a :: [*]
--   mkClient :: a -> Client a
--   mkState :: a -> IO (InputOutput (RouteState a))

-- instance PublishClient (IO (Output a, InputOutput r)) where
--   type Client (IO (Output a, InputOutput r)) = a -> IO ()
--   type RouteState (IO (Output a, InputOutput r)) = r
--   mkClient = undefined
--   mkState = undefined

-- instance (PublishClient a, PublishClient b) => PublishClient (a :<|> b) where
--   type Client (a :<|> b) = Client a :<|> Client b
--   type RouteState (a :<|> b) = MergedRoutes (RouteState a) (RouteState b)
--   mkClient (a :<|> b) = undefined
--   mkState (a :<|> b) = undefined

-- mPub
--   :: (HasNetwork a pc, HasNetwork b pc)
--   => Proxy pc -> Proxy (a :<|> b) -> RouteBuild (a :<|> b) r (Output a, Output b)
-- mPub pc (Proxy :: Proxy (a :<|> b)) = do
--   right <- networkNode pc pB
--   left <-  networkNode pc pA
--   return $ left :<|> right
--     where
--       pA = Proxy :: Proxy a
--       pB = Proxy :: Proxy b
