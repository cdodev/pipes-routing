{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveGeneric         #-}
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
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# OPTIONS_GHC -Wall #-}
module Pipes.Routing.Process where

import           Control.Concurrent.Async    (Async)
import           Control.Concurrent.Lifted   hiding (yield)
import           Control.Concurrent.STM.TVar
import           Control.Lens
import           Control.Monad.Reader
import           Control.Monad.State
import           Control.Monad.Trans.Control
import           Data.Serialize              (Serialize, decode, encode)
-- import Data.Functor.Contravariant
import           Data.Generics.Product
import           Data.Kind
import           Data.Monoid                 hiding (Alt)
import           Data.Proxy                  (Proxy (..))
import           Data.Singletons
import           Data.Singletons.TH          hiding ((:::))
import           Data.Singletons.TypeLits
-- import Data.Kind
import           Data.Text                   (Text)
import           GHC.Generics
import           GHC.TypeLits                (KnownSymbol, Symbol)
import           Pipes                       hiding (Proxy)
import           Pipes.Concurrent
import qualified Pipes.Prelude               as P
import           Servant.API
import           System.ZMQ4.Monadic         as ZMQ

import           Pipes.Routing.Ingest
import           Pipes.Routing.Types
-- -- import           Pipes.Routing.Publish


--------------------------------------------------------------------------------
type family ProcessInputs (api :: *) (chan :: k) :: [*] where
  ProcessInputs api (a :<+> b) = a ::: (ChannelType a api) ': ProcessInputs api b
  ProcessInputs api chan = '[chan ::: ChannelType chan api]


type family HasSingleField chan record b :: Constraint where
  HasSingleField ((chan :: Symbol) ::: a) record b = HasField chan (a -> b) record

type family HasFields (chans :: [*]) record b :: Constraint where
  HasFields (c ': rest) record b = (HasSingleField c record b, HasFields rest record b)
  HasFields '[] _ _ = ()

--------------------------------------------------------------------------------
newtype Joiner fields out r = Joiner r deriving (Generic)

makeWrapped ''Joiner

--------------------------------------------------------------------------------
mkProcessor
  :: (MonadReader r m, HasIngestSettings r
     , KnownSymbol subChan, KnownSymbol pushChan, Serialize a, Serialize b)
  => Proxy (subChan ::: a) -> Proxy (pushChan ::: b) -> (a -> b) -> m (ZMQ z (Async ()))
mkProcessor pSubChan pFanInChan f = do
  subAddr <- view recvFrom
  return $ do
    sub <- socket Sub
    ZMQ.connect sub subAddr
    push <- socket Push
    ZMQ.connect push pushConn
    let subP = sockSubscriber sub pSubChan
        pushC = sockPusher push
    async $ runEffect $ subP >-> P.map f >-> pushC
  where
    pushConn = "inproc://" ++ (nodeChannel $ chanP pFanInChan)

class MkFaninProcessor chans b pushChan r where
  runFanin
    ::(MonadReader s m, KnownSymbol pushChan, HasIngestSettings s, HasFields chans r b
      , Serialize a, Serialize b, Generic r)
    => Proxy chans -> Proxy (pushChan ::: b) -> r -> m (ZMQ z (Async ()))

instance MkFaninProcessor '[] b  pushChan r where
  runFanin _ _ _ = return (async (return ()))

instance (KnownSymbol subChan, Serialize a, Serialize b
         , HasField subChan (a -> b) r
         , HasFields rest r b
         , MkFaninProcessor rest b pushChan r)
  => MkFaninProcessor (subChan ::: a ': rest) b pushChan r where
  runFanin (Proxy :: Proxy (subChan ::: a ': rest))
           pPushChan
           r = do
    mkProcessor pSubChan pPushChan (getField @subChan r)
    -- runFanin pRest pPushChan r
    where
      pSubChan = Proxy :: Proxy (subChan ::: a)
      pRest  = Proxy :: Proxy rest
--------------------------------------------------------------------------------
class HasProcessor (api :: *) processor where
  type ProcessorT api processor (m :: * -> *) :: *
  data JoinerT api processor j :: *
  process :: Proxy api -> JoinerT api processor j -> ZMQ z (Processor api processor z)
  -- process ::

type Processor api processor z = ProcessorT api processor (ZMQ z)

--------------------------------------------------------------------------------
instance (Serialize out, KnownSymbol chan) => HasProcessor api (l :-> chan ::: (out :: *)) where
  type ProcessorT api (l :-> chan ::: out) m = Producer out m ()
  data JoinerT api (l :-> (chan ::: out)) r = Node (Joiner (l :-> (chan ::: out)) out r)
  process pApi (Node (joiner :: Joiner (l :-> chan ::: out) out r)) = do
    pull <- socket Pull
    ZMQ.bind pull pullConn
    -- runFanin 
    return $ sockPuller pFanInChan pull
    where
      pullConn = "inproc://" ++ (nodeChannel $ chanP pFanInChan)
      pFanInChan = Proxy :: Proxy (chan ::: out)
      mkFanIn chan = withSomeSing chan $ \(singChan :: SSymbol c) -> do
        undefined
        -- mkProcessor pChan pFanInChan (joiner ^. _Wrapped' . field @c)

        where
          pChan = Proxy :: Proxy (c ::: ChannelType c api)

instance (HasProcessor api l, HasProcessor api r) => HasProcessor api (l :<|> r) where
  type ProcessorT api (l :<|> r) m = ProcessorT api l m :<|> ProcessorT api r m
  data JoinerT api (l :<|> r) j = Alt (JoinerT api l j :<|> JoinerT api r j)
  process pApi (Alt (l :<|> r)) = do
    ta <- pa
    tb <- pb
    return $ ta :<|> tb
    where
      pa = process pApi l
      pb = process pApi r

data Ext = Ext {
    a :: Int -> String
  , b :: String -> String
  , c :: Double -> String
  } deriving (Generic)

type API = ("a" ::: Int :<|> "b" ::: String)
type Fs = ProcessInputs API ("a" :<+> "b")

type A = HasFields Fs Ext String

makeProc
  :: forall record fld . (HasFields Fs record String, HasField fld (Int -> String) record, Generic record)
  => Proxy fld -> record -> Int -> String
makeProc _ r i = getField @fld r i

s = makeProc (Proxy :: Proxy "a") (Ext show id show)
-- chanSym :: (KnownSymbol chan) =>  proxy chan -> Int
-- chanSym s = withSomeSing s $ \ sc -> withKnownSymbol sc _

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
type P1 = ("suite-start" :<+> "num") :-> ("ss-num" ::: Either String Int)
type P2 = "num" :-> ("show-num" ::: String)

type ProcessorAPI = P1 :<|> P2

type INum = "num" ::: Int
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
       "suite-start" ::: String
  :<|> "num" ::: Int


-- p :: ProcessorT INum PNum IO
-- p = intToString
-- pub :: PublisherT ProcessorAPI IO
-- pub = undefined

-- processorT :: ProcessorT InputEvents ProcessorAPI IO
-- processorT =
--        ssOrNum
--   :<|> intToString

-- type family HasChan (chan :: k) api :: Constraint where
--   HasChan c (c ::: a) = ()
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

  -- cn :: IsString a => EventScans -> a
  cn PassThrough   = "all-events"
  cn SuiteProgress = "suite-progress"

  |])

deriving instance Bounded EventScans
deriving instance Enum EventScans
deriving instance Eq EventScans
deriving instance Ord EventScans
deriving instance Show EventScans


channelName :: EventScans -> String
channelName PassThrough   = "all-events"
channelName SuiteProgress = "suite-progress"


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


forEvent :: EventScans -> (forall c. SEventScans c -> b) -> b
forEvent c f = withSomeSing c $ \(sc :: SEventScans c) -> f sc

 -- onEvent :: (Monad m) => IndexSubscription c -> EventPipe c m
-- onEvent AllEvents = cat
-- onEvent (ForSuite rid) = undefined
