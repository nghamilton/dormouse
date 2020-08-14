{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}

module Dormouse.Uri
  ( parseRequestFromUri
  , module Dormouse.Uri.Types
  , ensureHttp
  , ensureHttps
  , parseAbsoluteUri
  , parseRelativeUri
  , parseHttpUri
  , parseHttpsUri
  , (</>)
  , (?)
  , (&)
  , (=:)
  ) where

import Data.Bifunctor (first)
import Control.Exception.Safe (MonadThrow(..), throw, Exception(..), SomeException)
import qualified Data.ByteString as SB
import qualified Data.Text.Encoding as E
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LB
import qualified Data.List.NonEmpty as NL
import Data.Attoparsec.ByteString.Char8 (parseOnly)
import Data.CaseInsensitive (CI, foldedCase)
import Data.Proxy
import Data.Text (Text, unpack, pack)
import Data.Text.Encoding (encodeUtf8)
import Data.Typeable (Typeable, cast)
import Dormouse.Types (SomeDormouseException(..))
import Dormouse.Uri.Parser
import Dormouse.Uri.Types
import Dormouse.Uri.Query
import Dormouse.Uri.Encode
import GHC.TypeLits
import qualified Network.HTTP.Client as C
import qualified Network.HTTP.Types as T
import qualified Network.HTTP.Types.URI as UT

data UriException = forall ref scheme. UriException  {uriExceptionMessage :: Text}

instance Show (UriException) where
  show (UriException { uriExceptionMessage = message }) = "Failed to parse uri: " <> show message

instance Exception (UriException) where
  toException    = toException . SomeDormouseException
  fromException x = do
    SomeDormouseException a <- fromException x
    cast a

(</>) :: Uri ref scheme -> Text -> Uri ref scheme
(</>) (AbsoluteUri AbsUri {uriPath = path, .. }) text = AbsoluteUri $ AbsUri {uriPath = (Path {unPath =  (unPath path) ++ [PathSegment text] }), ..}
(</>) (RelativeUri RelUri {uriPath = path, .. }) text = RelativeUri $ RelUri {uriPath = (Path {unPath =  (unPath path) ++ [PathSegment text] }), ..}

ensureSchemeSymbol :: (KnownSymbol s, MonadThrow m) => Proxy s -> Uri ref scheme -> m (Uri 'Absolute s)
ensureSchemeSymbol prox (uri @ (AbsoluteUri (u @ AbsUri {uriScheme = scheme, ..}))) =  
  if (symbolVal prox == (unpack $ unScheme scheme)) then 
    return $ AbsoluteUri u
  else
    throw UriException { uriExceptionMessage = "Supplied Uri had a scheme of " <> (unScheme scheme) <> " which does not match the desired scheme of " <> (pack $ symbolVal prox) }
ensureSchemeSymbol prox (uri @ (RelativeUri _)) = throw UriException { uriExceptionMessage = "Provided URI was a Relative URI" }
ensureSchemeSymbol prox (AbsOrRelUri underlying) = ensureSchemeSymbol prox underlying

ensureHttp :: MonadThrow m => Uri ref scheme -> m (Uri 'Absolute "http")
ensureHttp uri = ensureSchemeSymbol (Proxy :: Proxy "http") uri

ensureHttps :: MonadThrow m => Uri ref scheme -> m (Uri 'Absolute "https")
ensureHttps uri = ensureSchemeSymbol (Proxy :: Proxy "https") uri

parseAbsoluteUri :: MonadThrow m => SB.ByteString -> m (Uri 'Absolute scheme)
parseAbsoluteUri bs = either (throw . UriException . pack) (return) $ parseOnly pAbsoluteUri bs

parseRelativeUri :: MonadThrow m => SB.ByteString -> m (Uri 'Relative scheme)
parseRelativeUri bs = either (throw . UriException . pack) (return) $ parseOnly pRelativeUri bs

parseHttpUri :: MonadThrow m => SB.ByteString -> m (Uri 'Absolute "http")
parseHttpUri text = do
  uri <- parseAbsoluteUri text
  httpUri <- ensureHttp uri
  return httpUri

parseHttpsUri :: MonadThrow m => SB.ByteString -> m (Uri 'Absolute "https")
parseHttpsUri text = do
  uri <- parseAbsoluteUri text
  httpsUri <- ensureHttps uri
  return httpsUri

parseRequestFromUri :: MonadThrow m => Uri 'Absolute scheme -> m C.Request
parseRequestFromUri (uri @ (AbsoluteUri AbsUri {uriScheme = scheme, uriAuthority = maybeAuth, uriPath = path, uriQuery = queryParams, uriFragment = fragment})) = do
  authority <- maybe (throw $ UriException { uriExceptionMessage = "Uri had no valid authority"} ) return maybeAuth
  let host = T.urlEncode False . encodeUtf8 . unHost . authorityHost $ authority
  let isSecure = (unScheme scheme) == "https"
  let port = maybe (if isSecure then 443 else 80) id (authorityPort authority)
  --let pathText = fmap unPathSegment $ unPath path
  let queryText = maybe "" (id) $ queryParams
  return $ C.defaultRequest
    { C.host = host
    , C.path = encodePath path
    , C.secure = isSecure
    , C.port = fromIntegral port
    , C.queryString = encodeQuery queryText
    }
