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
module Pipes.Routing.Types where

import           Data.Typeable        (Typeable)
import           GHC.TypeLits
import           Pipes                hiding (Proxy)
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

type family ChannelList (api :: *) :: [*] where
  ChannelList (c :> a) = '[c :> a]
  ChannelList (c :> a :<|> rest) = c :> a ': (ChannelList rest)
