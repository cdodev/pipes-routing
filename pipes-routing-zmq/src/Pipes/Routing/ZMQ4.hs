{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Pipes.Routing.ZMQ4 where

import Control.Monad.IO.Class
import Control.Monad.Reader

data ZMQConfig

newtype M m a = M { unM :: ReaderT ZMQConfig m a }
  deriving (MonadReader ZMQConfig, Functor, Applicative, Monad)
