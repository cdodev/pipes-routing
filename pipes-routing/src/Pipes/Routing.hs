{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PolyKinds           #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving  #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TupleSections #-}
{-# OPTIONS_GHC -Wall #-}

module Pipes.Routing
  -- ( EventScans(..)
  -- , sn
  -- , Sock
  -- , runSock
  -- )
  where

import           Control.Concurrent.Lifted hiding (yield)
import Control.Monad.Trans.Control
import           Control.Lens
-- import Data.Functor.Contravariant
import Data.Proxy (Proxy(..))
import           Data.Monoid
import           Data.Singletons
import           Data.Singletons.TH hiding ((:>))
import           Pipes hiding (Proxy)
import           Pipes.Concurrent
import qualified Pipes.Prelude             as P
import Servant.API


import Pipes.Routing.Types

data OK x where OK :: x => OK x

instance Show (OK x) where show _ = "OK"

isOK :: x => Proxy x -> OK x
isOK _ = OK

data TC a = TC deriving Show

tc :: Proxy x -> TC x
tc _ = TC

newtype AnEvent a = AnEvent a


--------------------------------------------------------------------------------
type InputEvents =
       "suite-start" :> String
  :<|> "num" :> Int


--------------------------------------------------------------------------------
suiteStartClient :: Sock String
intClient :: Sock Int

suiteStartClient :<|> intClient = publishClient (Proxy :: Proxy InputEvents)

--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
type Processor =
       ("suite-start" :<+> "num")
         :-> Either String Int
  :<|> "num" :-> String

type INum = "num" :> Int
type PNum = "num" :-> String

--------------------------------------------------------------------------------
type family ProcessInputs (api :: *) (chanName :: k) (m :: * -> *) :: * where
  ProcessInputs api (a :<+> b) m =
    (Producer (ChannelType a api) m (), Producer (ChannelType b api) m ())
  ProcessInputs api chanName m = Producer (ChannelType chanName api) m ()

--------------------------------------------------------------------------------
class HasProcessor (api :: *) processor where
  type ProcessorT api processor (m :: * -> *) :: *
  server :: Proxy api -> Proxy processor -> ProcessorM api processor
  -- process :: 

instance HasProcessor api (l :-> (out :: *)) where
  type ProcessorT api (l :-> out) m =
    ProcessInputs api l m -> m (Producer out m (), STM ())
  server _ _ = undefined

instance HasProcessor api (l :<|> r) where
  type ProcessorT api (l :<|> r) m = ProcessorT api l m :<|> ProcessorT api r m
  server _ _ = undefined


--------------------------------------------------------------------------------
type P = IO

type ProcessorM api processor = ProcessorT api processor P

data Merge a m b = Merge {
    _mergePrism :: Prism' b a
  , _mergeProducer  :: Producer a m ()
  }

-- makeLenses ''Merge

mergeProd
  :: (MonadBaseControl IO m, MonadIO m)
  => Merge a m c
  -> Merge b m c
  -> m (Producer c m (), STM ())
mergeProd (Merge ap as) (Merge bp bs) = do
  (ao, ai, seala) <- liftIO $ spawn' unbounded
  (bo, bi, sealb) <- liftIO $ spawn' unbounded
  _ <- fork $ runEffect $ as >-> toOutput (contramap (view $ re ap) ao)
  _ <- fork $ runEffect $ bs >-> toOutput (contramap (view $ re bp) bo)
  return (fromInput $ ai <> bi, seala >> sealb)

ssOrNum
  :: (Producer String P (), Producer Int P ())
  -> P (Producer (Either String Int) P (), STM ())
ssOrNum (ss, i) = mergeProd (Merge _Left ss) (Merge _Right i)

intToString
  :: Producer Int P ()
  -> P (Producer String P (), STM ())
intToString i = return (i >-> P.map show, return ())


p :: ProcessorT INum PNum IO
p = intToString

processor :: ProcessorT InputEvents Processor IO
processor =
       ssOrNum
  :<|> intToString

-- type family HasChan (chan :: k) api :: Constraint where
--   HasChan c (c :> a) = ()
--   HasChan (ChanName c) a = HasChan c a
--   HasChan c (a :<|> b) = Or (HasChan c a) (HasChan c b)


type family ChannelType (chan :: k) api :: * where
  ChannelType c (c :> a) = a
  ChannelType c ((c :> a) :<|> _) = a
  ChannelType c (_ :<|> a) = ChannelType c a

--------------------------------------------------------------------------------
getT :: Proxy api -> proxy a -> TC (ChannelType a api)
getT _ _ = TC
  
getP :: Proxy api -> proxy processor -> TC (ProcessorM api processor)
getP _ _ = TC
--------------------------------------------------------------------------------
$(singletons [d|
  data EventScans
    = PassThrough
    | SuiteProgress
  |])


deriving instance Bounded EventScans
deriving instance Enum EventScans
deriving instance Eq EventScans
deriving instance Ord EventScans
deriving instance Show EventScans

--------------------------------------------------------------------------------
data IndexEvent =
    SuiteStart Int
  | SuiteEnd Int
  | TestStart String
  | TestEnd String

type SuiteStartEnd = (Int, String)
--------------------------------------------------------------------------------
data IndexSubscription (idx :: EventScans) where
  AllEvents :: IndexSubscription 'PassThrough
  ForSuite :: Int -> IndexSubscription 'SuiteProgress

--------------------------------------------------------------------------------
type family IndexRequest (idx :: EventScans) :: *

type instance IndexRequest 'PassThrough = IndexEvent
-- type instance IndexRequest SuiteProgress = Types.BlazeEvent


--------------------------------------------------------------------------------
type family IndexResponse (idx :: EventScans) :: *

type instance IndexResponse 'PassThrough = IndexEvent

type EventPipe idx m = Pipe (IndexRequest idx) (IndexResponse idx) m ()
--------------------------------------------------------------------------------

affects :: IndexEvent -> EventScans -> Bool
_ `affects` PassThrough = True
_ `affects` _           = False

-- pick
--   :: (Typeable a, Monad m)
--   => Prism' Types.BlazeEvent a
--   -> Producer' Types.BlazeEvent m ()
--   -> Producer a m ()
-- pick p  prod = for prod $ \be -> case be ^? p of
--   Nothing -> return ()
--   Just a  -> yield a
 
-- mergeProd2
--   :: Merge a m x
--   -> Merge b m x
--   -> Merge c m x
--   -> IO (Producer x m (), STM ())
-- mergeProd2 ma mb mc = do
--   (px, seal1) <- mergeProd ma mb
--   (px', seal2) <- mergeProd (Merge id px) mc
--   return (px, seal1 >> seal2)
 
-- toIndexEvent :: Producer' Types.BlazeEvent m () -> Producer' IndexEvent m ()
-- toIndexEvent p = undefined

-- channelName :: EventScans -> Text
-- channelName PassThrough = "all-events"

-- forEvent :: EventScans -> (forall c. SEventScans c -> b) -> b
-- forEvent c f = withSomeSing c $ \(sc :: SEventScans c) -> f sc

 -- onEvent :: (Monad m) => IndexSubscription c -> EventPipe c m
-- onEvent AllEvents = cat
-- onEvent (ForSuite rid) = undefined
