{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeOperators             #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE UndecidableInstances      #-}
module Pipes.Routing.Operations where

import           Data.Proxy                  (Proxy (..))
import           GHC.TypeLits
import           Servant.API
import qualified GHC.TypeLits                as Ty
import Control.Lens hiding (imap)
import Prelude hiding ((>>=), (>>), return)
import Control.Monad.IO.Class (liftIO, MonadIO)
import Control.Monad.Indexed.State (IxMonadState(..), IxStateT(..))
import           Data.Typeable               (Typeable, cast)
import           Pipes.Concurrent
import Control.Monad.Indexed
import Control.Monad.Indexed.Trans (ilift)

import Pipes.Routing.HMap
import Pipes.Routing.Types


return :: (Monad m) => a -> IxStateT m si si a
return = ireturn

-- ibind :: (a -> m j k b) -> m i j a -> m i k b
(=<<) :: (Monad m) => (a -> IxStateT m q r b) -> IxStateT m p q a  -> IxStateT m p r b
(=<<) = ibind

(>>=) :: (Monad m) => IxStateT m p q a -> (a -> IxStateT m q r b) -> IxStateT m p r b
(>>=) = flip ibind

(>>) :: (Monad m) => IxStateT m p q a -> IxStateT m q r b -> IxStateT m p r b
v >> w = v >>= \_ -> w

-- imap :: (a -> b) -> f j k a -> f j k b
-- (<$>) :: (IxFunctor f) => (a -> b) -> f j k a -> f j k b
-- f <$> m = imap f m

execIxStateT :: Functor f => IxStateT f i j a -> i -> f j
execIxStateT m i = snd <$> runIxStateT m i

runIx = flip runIxStateT

data InputOutput chans = InOut {
    _inRoutes :: RouteMap Input chans
  , _outRoutes :: RouteMap Output chans
  } deriving (Typeable)

emptyInputOutput :: InputOutput '[]
emptyInputOutput = InOut emptyRoutes emptyRoutes


mergeInOut :: InputOutput a -> InputOutput b -> InputOutput (MergedRoutes a b)
mergeInOut (InOut ia oa) (InOut ib ob) = InOut (mergeRoutes ia ib) (mergeRoutes oa ob)

makeLenses ''InputOutput


type RouteBuild api (i :: [*]) = IxStateT IO (InputOutput i) (InputOutput (Chans api i))

class Channels api where
  type Chans api (i :: [*]) :: [*]
  mkChannels :: Proxy api -> RouteBuild api i (Output (Chan api))


instance (KnownSymbol chan, Typeable a, Chan (chan ::: a) ~ ty) => Channels (chan ::: a) where
  type Chans (chan ::: a) i = (chan ::: a) ': i
  mkChannels pApi = do
    (routes :: InputOutput i) <- iget
    (out :: Output ty, inp :: Input ty) <- ilift $ spawn unbounded
    let inp' = insert pApi pK inp $ routes ^. inRoutes
        out' = insert pApi pK out $ routes ^. outRoutes
    iput $ InOut inp' out'
    return out
    where pK = Proxy :: Proxy chan

