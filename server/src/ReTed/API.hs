{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}
module ReTed.API
  ( tedApi
  , tedServer
  ) where

import           Control.Monad (forM, liftM)
import           Control.Monad.IO.Class (liftIO)
import           Control.Monad.Trans.Except (ExceptT, throwE)
import           Data.Aeson (encode, decodeStrict)
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as L
import           Data.Maybe (catMaybes, fromMaybe)
import           Data.Monoid ((<>))
import           Data.Text (Text)
import           Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import           Database.Redis hiding (decode)
import qualified Filesystem.Path.CurrentOS as FS
import           Network.HTTP.Types (status200, status404)
import           Network.Wai (Application, Response, responseFile, responseLBS)
import           Servant
import           System.Random (randomRIO)

import Web.TED (FileType(..), Subtitle(..), queryTalk, toSub)
import qualified Web.TED as API
import ReTed.Config (Config(..))
import           ReTed.Models.Talk (Talk, getTalks, getTalkBySlug)
import ReTed.Types


instance FromHttpApiData FileType where
    parseUrlPiece "srt" = Right SRT
    parseUrlPiece "vtt" = Right VTT
    parseUrlPiece "txt" = Right TXT
    parseUrlPiece "lrc" = Right LRC
    parseUrlPiece _     = Left "Unsupported"

type TedApi =
       "talks" :> QueryParam "tid" Int
               :> QueryParam "limit" Int
               :> Get '[JSON] [Talk]
  :<|> "talks" :> "random"
               :> Get '[JSON] RedisTalk
  :<|> "talks" :> Capture "slug" Text
               :> Get '[JSON] Talk
  :<|> "talks" :> Capture "tid" Int
               :> "transcripts"
               :> Capture "format" FileType
               :> QueryParams "lang" Text
               :> Raw
  :<|> "talks" :> Capture "tid" Int
               :> "transcripts"
               :> "download"
               :> Capture "format" FileType
               :> QueryParams "lang" Text
               :> Raw
  :<|> "search" :> QueryParam "q" Text :> Get '[JSON] [RedisTalk]

type Handler = ExceptT ServantErr IO

notFound :: (Response -> t) -> t
notFound respond = respond $ responseLBS status404 [] "Not Found"

getTalksH :: Config -> Maybe Int -> Maybe Int -> Handler [Talk]
getTalksH config mStartTid mLimit = do
    talks <- liftIO $ getTalks conn limit
    return talks
  where
    conn = dbConn config
    defaultLimit = 10
    startTid = fromMaybe 0 mStartTid
    limit' = fromMaybe defaultLimit mLimit
    limit = if limit' > defaultLimit then defaultLimit else limit'

getTalkH :: Config -> Text -> Handler Talk
getTalkH config slug = do
    mTalk <- liftIO $ getTalkBySlug config slug
    case mTalk of
        Just talk -> return talk
        Nothing -> throwE err404

getSubtitlePath :: Connection -> Int -> FileType -> [Text] -> IO (Maybe FilePath)
getSubtitlePath conn tid format lang = do
    mTalk <- getTalkFromRedis conn tid
    case mTalk of
        Just talk -> toSub $
            Subtitle tid (slug talk) lang (mSlug talk) (mPad talk) format
        Nothing -> return Nothing

getTalkSubtitleH :: Connection -> Int -> FileType -> [Text] -> Application
getTalkSubtitleH conn tid format lang _ respond = do
    let cType = if format == VTT then "text/vtt" else "text/plain"
    path <- liftIO $ getSubtitlePath conn tid format lang
    case path of
        Just p  -> respond $ responseFile status200 [("Content-Type", cType)] p Nothing
        Nothing -> notFound respond

downloadTalkSubtitleH :: Connection
                      -> Int
                      -> FileType
                      -> [Text]
                      -> Application
downloadTalkSubtitleH conn tid format lang _ respond = do
    path <- liftIO $ getSubtitlePath conn tid format lang
    case path of
        Just p  -> do
            let filename = C.pack $ FS.encodeString $ FS.filename $ FS.decodeString p
            respond $ responseFile
                status200
                [ ("Content-Type", "text/plain")
                , ("Content-Disposition", "attachment; filename=" <> filename)]
                p
                Nothing
        Nothing -> notFound respond

getSearchH :: Connection -> Maybe Text -> Handler [RedisTalk]
getSearchH conn (Just q) = liftIO $ do
    searchtalks <- API.searchTalk q
    liftM catMaybes $ forM searchtalks $ \t -> do
        mtalk <- runRedis conn $ get (C.pack $ show $ API.s_id t)
        case mtalk of
            Right (Just talk') -> return $ decodeStrict talk'
            _                    -> do
                talk' <- queryTalk $ API.s_id t
                case talk' of
                    Nothing -> return Nothing
                    Just talk -> do
                        dbtalk <- marshal talk
                        runRedis conn $ multiExec $ do
                            set (C.pack $ show $ API.s_id t)
                                (L.toStrict $ encode dbtalk)
                            zadd "tids" [(realToFrac $ utcTimeToPOSIXSeconds $ publishedAt dbtalk, C.pack $ show $ API.s_id t)]
                        return $ Just dbtalk
getSearchH _ Nothing = throwE err400

getRandomTalkH :: Connection -> Handler RedisTalk
getRandomTalkH conn = do
    mTalk <- liftIO $ do
        mCount <- runRedis conn $ zcard "tids"
        case mCount of
            Right count -> do
                r <- randomRIO (0, count-1)
                mTid <- runRedis conn $ zrange "tids" r r
                getTalkFromRedis conn $ either (const 0) (read . C.unpack . head) mTid
            Left err -> error $ show err
    maybe (throwE err404) return mTalk

getTalkFromRedis :: Connection -> Int -> IO (Maybe RedisTalk)
getTalkFromRedis conn tid = do
    result <- runRedis conn $ get (C.pack $ show tid)
    either lhr rhr result
  where
    lhr = error . show
    rhr = return . maybe Nothing decodeStrict

tedApi :: Proxy TedApi
tedApi = Proxy

tedServer :: Config -> Server TedApi
tedServer config =
         getTalksH config
    :<|> getRandomTalkH conn
    :<|> getTalkH config
    :<|> getTalkSubtitleH conn
    :<|> downloadTalkSubtitleH conn
    :<|> getSearchH conn
  where
    conn = kvConn config
