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
{-# LANGUAGE UndecidableInstances       #-}
{-# OPTIONS_GHC -Wall #-}
module Pipes.Routing.Types where

import           Data.Typeable        (Typeable)
import           GHC.TypeLits
import           Servant

data (chan :: Symbol) ::: a
    deriving (Typeable)
infixr 4 :::

--------------------------------------------------------------------------------
data a :<+> b deriving Typeable

infixr 8 :<+>

--------------------------------------------------------------------------------
data (chanName :: k) :-> b
     deriving Typeable

infixr 9 :->
--------------------------------------------------------------------------------


type family ChannelType (chan :: k) api :: * where
  ChannelType c (c :> a) = a
  ChannelType c ((c :> a) :<|> _) = a
  ChannelType c (_ :<|> a) = ChannelType c a

type family ChannelList (api :: *) :: [*] where
  ChannelList (c :> a) = '[c :> a]
  ChannelList (c :> a :<|> rest) = c :> a ': (ChannelList rest)
