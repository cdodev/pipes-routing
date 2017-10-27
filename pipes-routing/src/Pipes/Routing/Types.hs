{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE PolyKinds                  #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# OPTIONS_GHC -Wall #-}
module Pipes.Routing.Types (
    (:::)
  , (:%::)
  , chanP
  , (:<+>)
  , (:->)
  , ChannelList
  , ChannelType
  , module Servant.API.Alternative
  ) where

import           Data.Typeable        (Typeable)
import           Servant.API.Alternative
import Servant
import Data.Singletons.TH

$(singletons [d|
  data (chan :: k) ::: a
      deriving (Typeable)
  -- infixr 4 :::

  |])

chanP :: Proxy (chan ::: a) -> Proxy chan
chanP _ = Proxy
--------------------------------------------------------------------------------
data a :<+> b deriving Typeable

infixr 8 :<+>

--------------------------------------------------------------------------------
data (chanName :: k) :-> b
     deriving Typeable

infixr 8 :->
--------------------------------------------------------------------------------

type family ChannelType (chan :: k) api :: * where
  ChannelType c (c ::: a) = a
  ChannelType c ((c ::: a) :<|> _) = a
  ChannelType c (_ :<|> a) = ChannelType c a

type family ChannelList (api :: *) :: [*] where
  ChannelList (c ::: a) = '[c ::: a]
  ChannelList (c ::: a :<|> rest) = (c ::: a) ': (ChannelList rest)
