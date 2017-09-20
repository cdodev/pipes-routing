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
module Pipes.Routing.Types where

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
-- | Union of two APIs, first takes precedence in case of overlap.
--
-- Example:
--
-- >>> :{
--type MyApi = "books" :> Get '[JSON] [Book] -- GET /books
--        :<|> "books" :> ReqBody '[JSON] Book :> Post '[JSON] () -- POST /books
-- :}


data a :<+> b deriving Typeable

infixr 8 :<+>

data ChanName (a :: Symbol) :: * deriving Typeable

newtype ProcessPipe a b = ProcessPipe (Pipe a b IO ()) deriving Typeable

data (chanName :: k) :-> b
     deriving Typeable

infixr 9 :->

-- $setup
-- >>> import Servant.API
-- >>> import Data.Aeson
-- >>> import Data.Text
-- >>> data Book
-- >>> instance ToJSON Book where { toJSON = undefined }
--------------------------------------------------------------------------------


type family ChannelType (chan :: k) api :: * where
  ChannelType c (c :> a) = a
  ChannelType c ((c :> a) :<|> _) = a
  ChannelType c (_ :<|> a) = ChannelType c a

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

class HasPublisher api context where
  type PublisherT api (m :: * -> *) :: *
  publishClient :: Proxy context -> Proxy api -> Publisher api

type Publisher api = PublisherT api Sock

instance (HasPublisher a context, HasPublisher b context) => HasPublisher (a :<|> b) context where
  type PublisherT (a :<|> b) m = PublisherT a m :<|> PublisherT b m
  publishClient pc (Proxy :: Proxy (a :<|> b)) =
    publishClient pc (Proxy :: Proxy a) :<|> publishClient pc (Proxy :: Proxy b)


instance (KnownSymbol name, Show a) => HasPublisher (name :> a) Debug where
  type PublisherT (name :> a) (m :: * -> *) = Sock a
  publishClient pc (Proxy :: Proxy (name :> a)) = undefined
    -- mkSock (symbolVal (Proxy :: Proxy name))
    where pc = Proxy :: Proxy context
