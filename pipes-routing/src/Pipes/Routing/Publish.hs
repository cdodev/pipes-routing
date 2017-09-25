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
module Pipes.Routing.Publish where

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
import Control.Monad.IO.Class (liftIO, MonadIO)
import Control.Monad.Indexed.State (IxMonadState(..), IxStateT(..))
import Control.Monad.Indexed.Trans (ilift)

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


class PublishClient a where
  type Client a :: *
  type RouteState a :: [*]
  mkClient :: a -> Client a
  mkState :: a -> IO (InputOutput (RouteState a))

instance PublishClient (IO (Output a, InputOutput r)) where
  type Client (IO (Output a, InputOutput r)) = a -> IO ()
  type RouteState (IO (Output a, InputOutput r)) = r
  mkClient = undefined
  mkState = undefined

instance (PublishClient a, PublishClient b) => PublishClient (a :<|> b) where
  type Client (a :<|> b) = Client a :<|> Client b
  type RouteState (a :<|> b) = MergedRoutes (RouteState a) (RouteState b)
  mkClient (a :<|> b) = undefined
  mkState (a :<|> b) = undefined

--------------------------------------------------------------------------------
class HasPublisher api context where
  type PublisherT api (m :: * -> *) :: *
  publishClient :: Proxy context -> Proxy api -> Publisher api


type Publisher api = PublisherT api IO --(RouteBuild api r)
-- type Publisher api i = PublisherT api (ExceptT Err IO)

data Debug


instance (HasPublisher a context, HasPublisher b context) => HasPublisher (a :<|> b) context where
  type PublisherT (a :<|> b) m = PublisherT a m :<|> PublisherT b m
  --   RouteBuild (a :<|> b) r (IxOutput (PublisherT (Chans b r) a m) :<|> IxOutput (PublisherT r b m))
  publishClient pc (Proxy :: Proxy (a :<|> b)) =
    publishClient pc pA :<|> publishClient pc pB
      where
        pA = Proxy :: Proxy a
        pB = Proxy :: Proxy b

instance (Typeable a, Channels (name :> a), KnownSymbol name, Show a) => HasPublisher (name :> a) Debug where
  type PublisherT (name :> a) (m :: * -> *) = IO (Output a, Input a, STM ())
  publishClient _pc _pApi = do
       (out, inp, seal) <- spawn' unbounded
       return (out, inp, seal)


-- mPub
--   :: (HasPublisher a pc, HasPublisher b pc)
--   => Proxy pc -> Proxy (a :<|> b) -> RouteBuild (a :<|> b) r (Output a, Output b)
-- mPub pc (Proxy :: Proxy (a :<|> b)) = do
--   right <- publishClient pc pB
--   left <-  publishClient pc pA
--   return $ left :<|> right
--     where
--       pA = Proxy :: Proxy a
--       pB = Proxy :: Proxy b
