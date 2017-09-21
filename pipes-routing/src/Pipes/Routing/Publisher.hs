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
module Pipes.Routing.Publisher where

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
newtype PublishM a r = PublishM { unPublishM :: Consumer a IO r } deriving (Functor, Applicative, Monad)

data Debug

data Err deriving Generic

-- instance Error Err
-- runChans :: (IxMonadState m, MonadIO (m i i)) => Proxy routes -> m i j a
-- runChans pRoutes = do
--   liftIO $ mkChannels pRoutes

class HasPublisher api context where
  type PublisherT api (m :: * -> *) :: *
  publishClient :: Proxy context -> Proxy api -> InputOutput i -> Publisher api i

type Publisher api i = PublisherT api (RouteBuild api i)
-- type Publisher api i = PublisherT api (ExceptT Err IO)

instance (HasPublisher a context, HasPublisher b context) => HasPublisher (a :<|> b) context where
  type PublisherT (a :<|> b) m = PublisherT a m :<|> PublisherT b m
  publishClient _pc (Proxy :: Proxy (a :<|> b)) i = _ -- do
    -- left <- publishClient pc (Proxy :: Proxy a) i
    -- right <- publishClient pc (Proxy :: Proxy b) _
    -- return left :<|> right

instance (Typeable a, Channels (name :> a), KnownSymbol name, Show a) => HasPublisher (name :> a) Debug where
  type PublisherT (name :> a) (m :: * -> *) = IO (Sock a)
  publishClient _pc pApi i = do
    nextState <- execIxStateT (mkChannels pApi) i
    let o = nextState ^. outRoutes . to (extract pApi pName)
    return $ Sock o
    -- mkSock (symbolVal (Proxy :: Proxy name))
    where pName = Proxy :: Proxy name
