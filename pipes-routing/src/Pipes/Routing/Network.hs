{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE DeriveFoldable             #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DeriveTraversable          #-}
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
module Pipes.Routing.Network where

import           Control.Lens
import           Control.Monad.IO.Class   (MonadIO, liftIO)
import           Data.IORef
import           Data.Typeable            (Typeable)
import           GHC.Generics             (Generic)
import           GHC.TypeLits
import           Pipes.Concurrent
import           Servant

import           Pipes.Routing.Operations hiding (return, (=<<), (>>), (>>=))
import           Pipes.Routing.Types


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
mkSock _ _ = do
  (o, i, _c) <- liftIO $ spawn' unbounded
  return (i, Sock o)

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
    _nodeIn   :: Output a
  , _nodeOut  :: Input a
  , _nodeSeal :: STM ()
  } deriving (Generic)

makeLenses ''Node

mkNode :: Buffer a -> IO (IORef (Node chan a))
mkNode x = do
  (o, i, s) <- spawn' x
  newIORef $ Node o i s

nodeChannel :: forall chan a. (KnownSymbol chan) => Node chan a -> String
nodeChannel _ = symbolVal (Proxy :: Proxy chan)

sendNode :: (KnownSymbol chan) => Node chan a -> a -> IO Bool
sendNode n a = do
  -- putStrLn $ "Sending to " ++ (nodeChannel n)
  atomically $ send (n ^. nodeIn) a

--------------------------------------------------------------------------------
class HasNetwork api where
  data NetworkT api (m :: * -> *) :: *
  networkNode :: Proxy api -> IO (Network api)


type Network api = NetworkT api IO --(RouteBuild api r)
-- type Network api i = NetworkT api (ExceptT Err IO)

data Debug

type family PublishChannels processor :: * where
  PublishChannels (a :<|> b) = (PublishChannels a) :<|> (PublishChannels b)
  PublishChannels (a :-> b) = b


instance (HasNetwork a , HasNetwork b ) => HasNetwork (a :<|> b) where
  data NetworkT (a :<|> b) m = NetworkAlt (NetworkT a m :<|> NetworkT b m)
  --   RouteBuild (a :<|> b) r (IxOutput (NetworkT (Chans b r) a m) :<|> IxOutput (NetworkT r b m))
  networkNode (Proxy :: Proxy (a :<|> b)) = do
    na <- networkNode pA
    nb <- networkNode pB
    return $ NetworkAlt (na :<|> nb)
      where
        pA = Proxy :: Proxy a
        pB = Proxy :: Proxy b

instance (Typeable a, Channels (name ::: (a :: *)), KnownSymbol name) => HasNetwork (name ::: a) where
  data NetworkT (name ::: a) (m :: * -> *) = NetworkLeaf ((IORef (Node name a)))
  networkNode _pApi = NetworkLeaf <$> mkNode unbounded

-- processorPublishClient
--   :: forall api pub. (HasNetwork api, (PublishChannels pub ~ api))
--   => Proxy pub -> Network api
-- processorPublishClient (Proxy :: Proxy pub) = networkNode pApi
--   where pApi = Proxy :: Proxy api


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
