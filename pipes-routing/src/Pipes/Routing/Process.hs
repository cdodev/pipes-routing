{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE QuasiQuotes           #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# OPTIONS_GHC -Wall #-}
module Pipes.Routing.Process where

import           Control.Concurrent.Lifted   hiding (yield)
import           Control.Lens
import           Control.Monad.Trans.Control
-- import Data.Functor.Contravariant
import           Data.Monoid
import           Data.Proxy                  (Proxy (..))
import           Data.Singletons
import           Data.Singletons.TH          hiding ((:>))
import           Pipes                       hiding (Proxy)
import           Pipes.Concurrent
import qualified Pipes.Prelude               as P
import GHC.TypeLits
import           Servant.API


import           Pipes.Routing.Types
import           Pipes.Routing.Publish



--------------------------------------------------------------------------------
type family ProcessInputs (api :: *) (chanName :: k) (m :: * -> *) :: * where
  ProcessInputs api (a :<+> b) m =
    (Producer (ChannelType a api) m (), Producer (ChannelType b api) m ())
  ProcessInputs api chanName m = Producer (ChannelType chanName api) m ()

--------------------------------------------------------------------------------
class HasProcessor (api :: *) processor where
  type ProcessorT api processor (m :: * -> *) :: *
  server :: Proxy api -> Proxy processor -> Processor api processor
  -- process ::

type Processor api processor = ProcessorT api processor P

instance (KnownSymbol chan) => HasProcessor api (l :-> chan :> (out :: *)) where
  type ProcessorT api (l :-> chan :> out) m =
    ProcessInputs api l m -> m (Producer out m (), STM ())
  server _ _ = undefined

instance HasProcessor api (l :<|> r) where
  type ProcessorT api (l :<|> r) m = ProcessorT api l m :<|> ProcessorT api r m
  server _ _ = undefined


--------------------------------------------------------------------------------
-- suiteStartClient :: Publisher String
-- intClient :: Publisher Int

-- suiteStartClient :<|> intClient = publishClient (Proxy :: Proxy Debug) (Proxy :: Proxy InputEvents)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
type P = IO


data Merge a m b = Merge {
    _mergePrism    :: Prism' b a
  , _mergeProducer :: Producer a m ()
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

--------------------------------------------------------------------------------
type P1 = ("suite-start" :<+> "num") :-> ("ss-num" :> Either String Int)
type P2 = "num" :-> ("show-num" :> String)

type ProcessorAPI = P1 :<|> P2

type INum = "num" :> Int
type PNum = "num" :-> String

--------------------------------------------------------------------------------

ssOrNum
  :: (Producer String P (), Producer Int P ())
  -> P (Producer (Either String Int) P (), STM ())
ssOrNum (ss, i) = mergeProd (Merge _Left ss) (Merge _Right i)

intToString
  :: Producer Int P ()
  -> P (Producer String P (), STM ())
intToString i = return (i >-> P.map show, return ())

type InputEvents =
       "suite-start" :> String
  :<|> "num" :> Int


-- p :: ProcessorT INum PNum IO
-- p = intToString
pub :: PublisherT ProcessorAPI IO
pub = undefined

processor :: ProcessorT InputEvents ProcessorAPI IO
processor =
       ssOrNum
  :<|> intToString

-- type family HasChan (chan :: k) api :: Constraint where
--   HasChan c (c :> a) = ()
--   HasChan (ChanName c) a = HasChan c a
--   HasChan c (a :<|> b) = Or (HasChan c a) (HasChan c b)


-- getT :: Proxy api -> proxy a -> TC (ChannelType a api)
-- getT _ _ = TC

-- getP :: Proxy api -> proxy processor -> TC (Processor api processor)
-- getP _ _ = TC
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