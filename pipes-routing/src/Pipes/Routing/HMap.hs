{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE DeriveDataTypeable        #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE FunctionalDependencies    #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE PolyKinds                 #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TemplateHaskell           #-}
{-# LANGUAGE TupleSections             #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE TypeOperators             #-}
{-# OPTIONS_GHC -Wall #-}
module Pipes.Routing.HMap where

import           Control.Lens
import           Control.Monad       (void)
import           Data.Map.Strict     (Map)
import qualified Data.Map.Strict     as Map
import           Data.Maybe          (fromJust)
import           Data.Proxy          (Proxy (..))
import           Data.Text           (Text)
import           Data.Text.Lens      (packed)
import           Data.Typeable       (Typeable, cast)
import           GHC.Exts
import           GHC.TypeLits
import qualified GHC.TypeLits        as Ty
import           Pipes.Concurrent
import           Pipes.Routing.Types
import           Servant.API

data SomeVal f = forall a. Typeable a => I (f a)
newtype RouteMap (f :: * -> *) (a :: [*]) = Routes { unRoutes :: Map Text (SomeVal f) }

emptyRoutes :: RouteMap f '[]
emptyRoutes = Routes Map.empty

getInbox :: (Typeable a, Typeable f) => SomeVal f -> Maybe (f a)
getInbox (I i) = cast i

type family RouteElem (r :: *) (routes :: [*]) :: Constraint where
  RouteElem (k :> i) '[] = TypeError ('Ty.Text "Route not found")
  RouteElem (k :> i) (k :> i ': xs) = ()
  RouteElem (k :> i) (a ': as) = RouteElem (k :> i) as

insert
  :: (KnownSymbol k, Typeable i, ChannelType k api ~ i)
  => Proxy api -> Proxy k -> f i -> RouteMap f routes -> RouteMap f ((k :> i) ': routes)
insert _ pKey i = Routes . Map.insert k (I i) . unRoutes
  where
    k = (symbolVal pKey) ^. packed

extract
  :: ( KnownSymbol k, Typeable i, Typeable f
     , ChannelType k api ~ i
     , RouteElem (k :> i) routes
     )
  => Proxy api -> Proxy k -> RouteMap f routes -> f i
extract _ pKey (Routes m) = fromJust $ Map.lookup k m >>= getInbox
  where
    k = (symbolVal pKey) ^. packed

--------------------------------------------------------------------------------
type API = "a" :> Int :<|> "b" :> String

pApi :: Proxy API
pApi = Proxy :: Proxy API

main :: IO ()
main = do
  (oa, ia) <- spawn unbounded
  (ob, ib) <- spawn unbounded
  let p = insert pApi (Proxy :: Proxy "b") ib emptyRoutes
      p1 = insert pApi (Proxy :: Proxy "a") ia p
      chanA = extract pApi (Proxy :: Proxy "a") p1
      chanB = extract pApi (Proxy :: Proxy "b") p1
  void $ atomically $ do
    void $ send oa 1
    void $ send ob "test"
  print =<< (atomically $ (,) <$> recv chanA <*> recv chanB)





