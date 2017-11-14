{-# LANGUAGE AllowAmbiguousTypes       #-}
{-# LANGUAGE ConstraintKinds           #-}
{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE GADTs                     #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE PolyKinds                 #-}
{-# LANGUAGE QuasiQuotes               #-}
{-# LANGUAGE RankNTypes                #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE StandaloneDeriving        #-}
{-# LANGUAGE TemplateHaskell           #-}
{-# LANGUAGE TupleSections             #-}
{-# LANGUAGE TypeApplications          #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE TypeOperators             #-}
{-# LANGUAGE UndecidableInstances      #-}
{-# OPTIONS_GHC -Wall #-}
module Pipes.Routing.Process where

import           Control.Concurrent.Async  (Async)
import           Control.Lens
import           Control.Monad             (void)
import           Data.Generics.Product     (HasField, getField)
import           Data.Kind                 (Constraint)
import           Data.Serialize            (Serialize)
import           GHC.Generics              (Generic)
import           Pipes                     (Producer, yield, (>->), lift)
import qualified Pipes                     as Pipes
import qualified Pipes.Prelude             as P
import           System.ZMQ4.Monadic       as ZMQ

import           Pipes.Routing.Ingest      (ZMQRouter, recvFrom, retagRouter,
                                            sendTo)
import           Pipes.Routing.Types
import           Pipes.Routing.ZMQ         (nodeChannel, sockPublisher,
                                            sockPuller, sockPusher,
                                            sockSubscriber)


--------------------------------------------------------------------------------
type family ProcessInputs (api :: *) (chan :: k) :: [*] where
  ProcessInputs api (a :<+> b) = (a ::: (ChannelType a api)) ': ProcessInputs api b
  ProcessInputs api chan = '[chan ::: ChannelType chan api]

type family ProcessorAPI (processor :: *) :: * where
  ProcessorAPI (_ :-> (chan ::: a)) = chan ::: a
  ProcessorAPI (l :<|> r) = ProcessorAPI l :<|> ProcessorAPI r

type family HasSingleField chan record b :: Constraint where
  HasSingleField ((chan :: Symbol) ::: a) record b = HasField chan (a -> b) record

type family HasFields (chans :: [*]) record b :: Constraint where
  HasFields (c ': rest) record b = (HasSingleField c record b, HasFields rest record b)
  HasFields '[] _ _ = ()

--------------------------------------------------------------------------------
type family AllSerializable (api :: *) :: Constraint where
  AllSerializable (_ ::: a) = Serialize a
  AllSerializable (l :<|> r) = (AllSerializable l, AllSerializable r)

--------------------------------------------------------------------------------
data Joiner fields out = forall r .
  ( HasFields fields r out
  , Generic r
  ) => Joiner { joinRecords :: r }

retagJoiner :: Joiner (chan ': rest) out -> Joiner rest out
retagJoiner (Joiner r) = Joiner r

--------------------------------------------------------------------------------
mkProcessor
  :: (KnownSymbol subChan, KnownSymbol pushChan, Serialize a, Serialize b)
  => (ZMQRouter r)
  -> Proxy (subChan ::: a)
  -> Proxy (pushChan ::: b)
  -> (a -> b)
  -> ZMQ z (Async ())
mkProcessor zmqRouter pSubChan pFanInChan f = do
  -- liftIO $ putStrLn ( "mkProcessor "
                      -- ++ (nodeChannel $ chanP pFanInChan)
                      -- ++ " <- "
                      -- ++ (nodeChannel $ chanP pSubChan))
  let subAddr = zmqRouter ^. recvFrom
  sub <- socket Sub
  ZMQ.connect sub subAddr
  push <- socket Push
  ZMQ.connect push pushConn
  let subP = sockSubscriber sub pSubChan
      pushC = sockPusher push
  async $ Pipes.runEffect $ subP >-> P.map f >-> pushC
  where
    pushConn = "inproc://" ++ (nodeChannel $ chanP pFanInChan)

--------------------------------------------------------------------------------
class MkFaninProcessor chans b pushChan where
  runFanin
    ::( KnownSymbol pushChan , Serialize b)
    => (ZMQRouter r)
    -> Proxy chans
    -> Proxy (pushChan ::: b)
    -> Joiner chans b
    -> ZMQ z (Async ())

instance MkFaninProcessor '[] b  pushChan where
  runFanin _ _ _ _ = (async (return ()))

instance forall subChan a b rest pushChan.
         ( KnownSymbol subChan, Serialize a, Serialize b
         , MkFaninProcessor rest b pushChan
         )
  => MkFaninProcessor (subChan ::: a ': rest) b pushChan where
  runFanin s (Proxy :: Proxy (subChan ::: a ': rest))
           pPushChan
           joiner@(Joiner r) = do
    -- liftIO $ putStrLn ("runFanin " ++ symbolVal (Proxy :: Proxy subChan))
    void $ mkProcessor s pSubChan pPushChan (getField @subChan r)
    runFanin s pRest pPushChan (retagJoiner joiner)
    where
      pSubChan = Proxy :: Proxy (subChan ::: a)
      pRest  = Proxy :: Proxy rest

--------------------------------------------------------------------------------
class HasProcessor (api :: *) processor where
  type ProcessorT api processor (m :: * -> *) :: *
  data JoinerT api processor :: *
  process
    :: (ZMQRouter api)
    -> JoinerT api processor
    -> ZMQ z (Processor api processor z)
  -- process ::

type Processor api processor z = ProcessorT api processor (ZMQ z)

--------------------------------------------------------------------------------
instance
  ( Serialize out, KnownSymbol chan
  , MkFaninProcessor (ProcessInputs api l) out chan
  )
  => HasProcessor api (l :-> chan ::: (out :: *)) where
  type ProcessorT api (l :-> chan ::: out) m = Producer out m ()
  data JoinerT api (l :-> (chan ::: out)) = Node (Joiner (ProcessInputs api l) out)
  process zmqRouter (Node joiner) = do
    pull <- socket Pull
    ZMQ.bind pull pullConn
    void $ runFanin zmqRouter pJoinChans pFanInChan joiner
    sock <- ZMQ.socket Pub -- ZMQ.async (go s)
    ZMQ.connect sock (zmqRouter ^. sendTo)
    liftIO $ putStrLn ("process faninchan: " ++ (nodeChannel $ chanP pFanInChan))
    let p = sockPuller pFanInChan pull
        pub = sockPublisher sock pFanInChan
    return $ Pipes.for p $ \i -> do
      lift $ Pipes.runEffect $ (yield i) >-> pub
      yield i
    where
      pJoinChans = Proxy :: Proxy ((ProcessInputs api l))
      pullConn = "inproc://" ++ (nodeChannel $ chanP pFanInChan)
      pFanInChan = Proxy :: Proxy (chan ::: out)

instance (HasProcessor api l, HasProcessor api r) => HasProcessor api (l :<|> r) where
  type ProcessorT api (l :<|> r) m = ProcessorT api l m :<|> ProcessorT api r m
  data JoinerT api (l :<|> r) = Alt (JoinerT api l :<|> JoinerT api r)
  process zmqRouter (Alt (l :<|> r)) = do
    ta <- pa
    tb <- pb
    return $ ta :<|> tb
    where
      pa = process zmqRouter l
      pb = process zmqRouter r

runProcessor
  :: (HasProcessor api processor) => ZMQRouter api
     -> JoinerT api processor
     -> ZMQ z (ZMQRouter (CombineApis api (ProcessorAPI processor)), ProcessorT api processor (ZMQ z))
runProcessor zmqRouter j = (retagRouter zmqRouter,) <$> process zmqRouter j


data IA = IA { int :: Int -> (Int, Int) } deriving Generic

ia :: IA
ia = IA $ \(i :: Int) -> (i, i + 10)

iaj :: Joiner '["int" ::: Int] (Int, Int)
iaj = Joiner ia

-- chanSym :: (KnownSymbol chan) =>  proxy chan -> Int
-- chanSym s = withSomeSing s $ \ sc -> withKnownSymbol sc _

--------------------------------------------------------------------------------
-- suiteStartClient :: Publisher String
-- intClient :: Publisher Int

-- suiteStartClient :<|> intClient = publishClient (Proxy :: Proxy Debug) (Proxy :: Proxy InputEvents)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------



-- getT :: Proxy api -> proxy a -> TC (ChannelType a api)
-- getT _ _ = TC

-- getP :: Proxy api -> proxy processor -> TC (Processor api processor)
-- getP _ _ = TC
--------------------------------------------------------------------------------
-- $(singletons [d|
--   data EventScans
--     = PassThrough
--     | SuiteProgress

--   -- cn :: IsString a => EventScans -> a
--   cn PassThrough   = "all-events"
--   cn SuiteProgress = "suite-progress"

--   |])

-- deriving instance Bounded EventScans
-- deriving instance Enum EventScans
-- deriving instance Eq EventScans
-- deriving instance Ord EventScans
-- deriving instance Show EventScans


-- channelName :: EventScans -> String
-- channelName PassThrough   = "all-events"
-- channelName SuiteProgress = "suite-progress"


--------------------------------------------------------------------------------
-- data IndexEvent =
--     SuiteStart Int
--   | SuiteEnd Int
--   | TestStart String
--   | TestEnd String

-- type SuiteStartEnd = (Int, String)
-- --------------------------------------------------------------------------------
-- data IndexSubscription (idx :: EventScans) where
--   AllEvents :: IndexSubscription 'PassThrough
--   ForSuite :: Int -> IndexSubscription 'SuiteProgress

-- --------------------------------------------------------------------------------
-- type family IndexRequest (idx :: EventScans) :: *

-- type instance IndexRequest 'PassThrough = IndexEvent
-- -- type instance IndexRequest SuiteProgress = Types.BlazeEvent


-- --------------------------------------------------------------------------------
-- type family IndexResponse (idx :: EventScans) :: *

-- type instance IndexResponse 'PassThrough = IndexEvent

-- type EventPipe idx m = Pipe (IndexRequest idx) (IndexResponse idx) m ()
-- --------------------------------------------------------------------------------

-- --------------------------------------------------------------------------------
-- affects :: IndexEvent -> EventScans -> Bool
-- _ `affects` PassThrough = True
-- _ `affects` _           = False

-- -- pick
-- --   :: (Typeable a, Monad m)
-- --   => Prism' Types.BlazeEvent a
-- --   -> Producer' Types.BlazeEvent m ()
-- --   -> Producer a m ()
-- -- pick p  prod = for prod $ \be -> case be ^? p of
-- --   Nothing -> return ()
-- --   Just a  -> yield a

-- -- mergeProd2
-- --   :: Merge a m x
-- --   -> Merge b m x
-- --   -> Merge c m x
-- --   -> IO (Producer x m (), STM ())
-- -- mergeProd2 ma mb mc = do
-- --   (px, seal1) <- mergeProd ma mb
-- --   (px', seal2) <- mergeProd (Merge id px) mc
-- --   return (px, seal1 >> seal2)

-- -- toIndexEvent :: Producer' Types.BlazeEvent m () -> Producer' IndexEvent m ()
-- -- toIndexEvent p = undefined


-- forEvent :: EventScans -> (forall c. SEventScans c -> b) -> b
-- forEvent c f = withSomeSing c $ \(sc :: SEventScans c) -> f sc

--  -- onEvent :: (Monad m) => IndexSubscription c -> EventPipe c m
-- -- onEvent AllEvents = cat
-- -- onEvent (ForSuite rid) = undefined

--------------------------------------------------------------------------------
-- subscribeToApi
--   :: forall api chans z b.
--      (Serialize b, AllSerializable api, SingI (Chans api), ChannelList api ~ chans)
--   => Socket z Sub
--   -> Proxy (api :: *)
--   -> Joiner chans b
--   -> Producer b (ZMQ z) ()
-- subscribeToApi sub pApi joiner@(Joiner j) = do
--   lift $ forM_ subChans (ZMQ.subscribe sub)
--   forever $ do
--     [chan', bs] <- lift $ ZMQ.receiveMulti sub
--     let (chan :: Text) = undefined
--     withSomeSing chan $ \(sc :: SSymbol s) ->
--       case decodeChan pApi (Proxy :: Proxy s) bs of
--         Left e -> liftIO $ print e
--         Right a -> yield (getField @s j $ a)
--     -- liftIO $ print (chan, bs)
--     -- yield (bs ^?! to decode . _Right)
--   where
--     subChans = (channelList pApi) ^.. traversed . re utf8

-- decodeChan :: (AllSerializable api, ChannelType chan api ~ a, Serialize a) => Proxy api -> Proxy chan -> ByteString -> Either String a
-- decodeChan pApi pChan bs = decode bs
