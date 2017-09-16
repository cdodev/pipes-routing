{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveFunctor      #-}
{-# LANGUAGE DeriveFoldable     #-}
{-# LANGUAGE DeriveTraversable  #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators      #-}
{-# LANGUAGE PolyKinds #-}
module Pipes.Routing.Types where

import           Pipes  hiding (Proxy) -- (MonadIO, Pipe, Consumer)
import qualified Pipes as P
import GHC.Generics (Generic)
import GHC.TypeLits
import           Data.Semigroup   (Semigroup (..))
import           Data.Typeable    (Typeable)
import Control.Monad.Except
import Data.Proxy
import Servant
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
type Sock m a = Consumer a m ()

mkSock :: (Show a, MonadIO m) => String -> Sock m a
mkSock chanName = P.await >>= (liftIO . print . (chanName,))

runSock :: Monad m => Sock m t -> t -> m ()
runSock f t = runEffect $ yield t >-> f

---------------------------------------------------------------------------------
newtype PublishM a r = PublishM { unPublishM :: Consumer a IO r } deriving (Functor, Applicative, Monad)

data Debug

data Err deriving Generic

-- instance Error Err

class HasPublisher api context where
  type PublisherT api (m :: * -> *) :: *
  publishClient :: Proxy context -> Proxy api -> Publisher api

type Publisher api = PublisherT api (ExceptT Err IO)

instance (HasPublisher a context, HasPublisher b context) => HasPublisher (a :<|> b) context where
  type PublisherT (a :<|> b) m = PublisherT a m :<|> PublisherT b m
  publishClient pc (Proxy :: Proxy (a :<|> b)) =
    publishClient pc (Proxy :: Proxy a) :<|> publishClient pc (Proxy :: Proxy b)


instance (KnownSymbol name, Show a) => HasPublisher (name :> a) Debug where
  type PublisherT (name :> a) (m :: * -> *) = Sock m a
  publishClient pc (Proxy :: Proxy (name :> a)) =
    mkSock (symbolVal (Proxy :: Proxy name))
    where pc = Proxy :: Proxy context
