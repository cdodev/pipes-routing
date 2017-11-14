{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE DeriveDataTypeable        #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE FunctionalDependencies    #-}
{-# LANGUAGE InstanceSigs              #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE PolyKinds                 #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TemplateHaskell           #-}
{-# LANGUAGE TupleSections             #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE TypeOperators             #-}
{-# LANGUAGE UndecidableInstances      #-}
{-# LANGUAGE ViewPatterns              #-}
{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -fno-warn-unticked-promoted-constructors #-}
module Pipes.Routing.HMap where

import           Control.Lens
-- -- -- import           Control.Monad               (void)
-- -- -- import Control.Monad.IO.Class (liftIO, MonadIO)
-- -- -- import Control.Monad.Indexed.State (IxMonadState(..), IxStateT(..))
-- -- -- import Control.Monad.Indexed.Trans (ilift)
import           Data.Map.Strict             (Map)
import qualified Data.Map.Strict             as Map
import           Data.Maybe                  (fromJust)
import           Data.Promotion.Prelude.List ((:++))
import           Data.Proxy                  (Proxy (..))
import           Data.Text                   (Text)
import           Data.Text.Lens              (packed)
import           Data.Typeable               (Typeable, cast)
import           GHC.Exts
import           GHC.TypeLits
import qualified GHC.TypeLits                as Ty
-- -- -- import           Pipes.Concurrent
import           Pipes.Routing.Types

data SomeVal f = forall a. Typeable a => I (f a)
newtype RouteMap (f :: * -> *) (a :: [*]) = Routes { unRoutes :: Map Text (SomeVal f) }

emptyRoutes :: RouteMap f '[]
emptyRoutes = Routes Map.empty

getInbox :: (Typeable a, Typeable f) => SomeVal f -> Maybe (f a)
getInbox (I i) = cast i

type family RouteElem (r :: *) (routes :: [*]) :: Constraint where
  RouteElem (k ::: i) '[] = TypeError (('Ty.Text "Route '") :<>: ('ShowType (k ::: i)) :<>: ('Ty.Text "' not found"))
  RouteElem (k ::: i) (k ::: i ': xs) = ()
  RouteElem (k ::: i) (a ': as) = RouteElem (k ::: i) as

type MergedRoutes a b = a :++ b

insert
  :: (KnownSymbol k, Typeable i, ChannelType k api ~ i)
  => Proxy api -> Proxy k -> f i -> RouteMap f routes -> RouteMap f ((k ::: i) ': routes)
insert _ pKey i = Routes . Map.insert k (I i) . unRoutes
  where
    k = (symbolVal pKey) ^. packed

extract
  :: ( KnownSymbol k, Typeable i, Typeable f
     , ChannelType k api ~ i
     , RouteElem (k ::: i) routes
     )
  => Proxy api -> Proxy k -> RouteMap f routes -> f i
extract _ pKey (Routes m) = fromJust $ Map.lookup k m >>= getInbox
  where
    k = (symbolVal pKey) ^. packed

mergeRoutes :: RouteMap f a -> RouteMap f b -> RouteMap f (MergedRoutes a b)
mergeRoutes (unRoutes -> a) (unRoutes -> b) = Routes $ Map.union a b

--------------------------------------------------------------------------------


-- instance (Channels a, Channels b) => Channels (a :<|> b) where
--   type Chans (a :<|> b) =  (Chans a) :++ (Chans b)
--   mkChannels _ = do
--     (riA, roA) <- mkChannels (Proxy :: Proxy a)
--     (riB, roB) <- mkChannels (Proxy :: Proxy b)
--     return (mergeRoutes riA riB, mergeRoutes roA roB)

--------------------------------------------------------------------------------
type API = "a" ::: Int :<|> "b" ::: String :<|> "c" ::: Double

-- api :: Proxy API
-- api = Proxy :: Proxy API

-- chans :: IO (RouteMap Input (ChannelList API) , RouteMap Output (ChannelList API))
-- chans = mkChannels api

-- main :: IO ()
-- main = do
--   (oa, ia) <- spawn unbounded
--   (ob, ib) <- spawn unbounded
--   let p = insert api (Proxy :: Proxy "b") ib emptyRoutes  -- :: RouteMap Input (ChannelList ("b" ::: String))
--       p1 = insert api (Proxy :: Proxy "c") ia p
--       chanA = extract api (Proxy :: Proxy "c") p1
--       chanB = extract api (Proxy :: Proxy "b") p1
--   void $ atomically $ do
--     void $ send oa 1
--     void $ send ob "test"
--   print =<< (atomically $ (,) <$> recv chanA <*> recv chanB)
