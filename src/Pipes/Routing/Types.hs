{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE DeriveDataTypeable        #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE GADTs                     #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE PolyKinds                 #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TemplateHaskell           #-}
{-# LANGUAGE TupleSections             #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE TypeOperators             #-}
{-# LANGUAGE UndecidableInstances      #-}
{-# OPTIONS_GHC -Wall #-}
module Pipes.Routing.Types (
    (:::)
  , (:%::)
  , chanP
  , (:<+>)
  , (:->)
  , ChannelList, channelList
  , Chans
  , ChannelType
  , CombineApis
  , module Servant.API.Alternative
  , module Data.Typeable
  , module GHC.TypeLits
  ) where

import           Data.Serialize               (Serialize)
import           Data.Singletons              (Apply, SingI, TyFun,
                                               fromSing, singByProxy)
import           Data.Singletons.Prelude.List (Map)
import           Data.Singletons.TH           (singletons)
import           Data.Text                    (Text)
import           Data.Typeable                (Typeable, Proxy(..))
import           GHC.TypeLits                 (Symbol, KnownSymbol, symbolVal)
import           Servant.API.Alternative      ((:<|>) (..))

$(singletons [d|
  data (Serialize a) => (chan :: k) ::: a
      deriving (Typeable)
  -- infixr 4 :::

  |])

chanP :: Proxy (chan ::: a) -> Proxy chan
chanP _ = Proxy
--------------------------------------------------------------------------------
data a :<+> b deriving Typeable

infixr 8 :<+>

-- data api :=> processor deriving Typeable
--------------------------------------------------------------------------------
data (chanName :: k) :-> b
     deriving Typeable

infixr 8 :->

--------------------------------------------------------------------------------
type family ChanName (someChan :: *) :: Symbol where
  ChanName (chan ::: _) = chan

data SChanName (chan :: TyFun * Symbol)

type instance Apply SChanName chan = ChanName chan

type Chans api = Map SChanName (ChannelList api)

type family ChannelType (chan :: k) api :: * where
  ChannelType c (c ::: a) = a
  ChannelType c ((c ::: a) :<|> _) = a
  ChannelType c (_ :<|> a) = ChannelType c a

type family CombineApis (l :: *) (r :: *) :: * where
  CombineApis () r = r
  CombineApis l () = l
  CombineApis (l :<|> lr) r = l :<|> CombineApis lr r
  CombineApis l r  = l :<|> r

--------------------------------------------------------------------------------
type family ChannelList (api :: k) :: [*] where
  ChannelList (c ::: a) = '[c ::: a]
  ChannelList (c ::: a :<|> rest) = (c ::: a) ': (ChannelList rest)

--------------------------------------------------------------------------------
channelList :: forall api . (SingI (Chans api)) => Proxy api -> [Text]
channelList _ = fromSing $ singByProxy pChans
  where
    pChans = Proxy :: Proxy (Chans api)
