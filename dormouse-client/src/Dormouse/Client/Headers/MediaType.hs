{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Dormouse.Client.Headers.MediaType 
  ( MediaType(..)
  , ContentType(..)
  , MediaTypeException
  , AcceptHeader
  , acceptHeader
  , encodeAcceptHeader
  , parseMediaType
  , encodeMediaType
  , applicationJson
  , applicationXWWWFormUrlEncoded
  , textHtml
  ) where

import Control.Exception.Safe (MonadThrow, throw)
import Control.Applicative ((<|>))
import qualified Data.ByteString as B
import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.CaseInsensitive  (CI, mk, foldedCase)
import Dormouse.Client.Exception (MediaTypeException(..))
import qualified Data.Char as C
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Text.Printf as P

-- | A Media Type indicates the format of content which can be transferred over the wire
data MediaType = MediaType 
  { mainType :: ContentType -- ^ The general category of data associated with this Media Type
  , subType :: CI B.ByteString -- ^ The subtype indicates the exact subtype of data associated with this Media Type
  , suffixes :: [CI B.ByteString] -- ^ The suffixes specify additional information on the structure of this Media Type
  , parameters :: Map.Map (CI B.ByteString) B.ByteString -- ^ Parameters serve to modify the content subtype specifying additional information, e.g. the @charset@
  } deriving (Eq, Ord, Show)

data ContentType
  = Text
  | Image
  | Audio
  | Video
  | Application
  | Multipart
  | Other (CI B.ByteString)
  deriving (Eq, Ord, Show)

newtype AcceptWithQValue = AcceptWithQValue { unAcceptWithQValue :: (MediaType, Maybe Double) } 
  deriving Eq

instance Ord AcceptWithQValue where
  compare (AcceptWithQValue (m1, Nothing)) (AcceptWithQValue (m2, Nothing)) = compare m1 m2
  compare (AcceptWithQValue (m1, Just q1)) (AcceptWithQValue (m2, Just q2)) = thenCompare m1 m2 $ compare q1 q2
  compare (AcceptWithQValue (_, Nothing)) (AcceptWithQValue (_, Just _))    = LT
  compare (AcceptWithQValue (_, Just _)) (AcceptWithQValue (_, Nothing))    = GT

thenCompare :: Ord a => a -> a -> Ordering -> Ordering 
thenCompare a1 a2 EQ  = compare a1 a2
thenCompare _  _  o = o

newtype AcceptHeader = AcceptHeader { unAcceptHeader :: Set.Set AcceptWithQValue }
  deriving (Eq, Ord, Semigroup, Monoid)

acceptHeader :: MediaType -> Maybe Double -> AcceptHeader
acceptHeader mt (Just q) | q > 1.0 = AcceptHeader (Set.fromList [ AcceptWithQValue (mt, Just 1.0) ])
acceptHeader mt q                  = AcceptHeader (Set.fromList [ AcceptWithQValue (mt, q) ])

encodeAcceptHeader :: AcceptHeader -> B.ByteString 
encodeAcceptHeader (AcceptHeader acceptQValues) = Set.foldl' folder B.empty acceptQValues
  where
    folder acc (AcceptWithQValue(mt, Just q)) = acc <> "," <> encodeMediaType (stripSuffixParams mt) <> ";q=" <> TE.encodeUtf8 (T.pack (P.printf "%.3f" q))
    folder acc (AcceptWithQValue(mt, Nothing)) = acc <> "," <> encodeMediaType (stripSuffixParams mt)
    stripSuffixParams mt = mt { suffixes = [], parameters = Map.empty }

-- | Encode a Media Type as an ASCII ByteString
encodeMediaType :: MediaType -> B.ByteString
encodeMediaType mediaType =
  let mainTypeBs = foldedCase . mainTypeAsByteString $ mainType mediaType
      subTypeBs = foldedCase $ subType mediaType
      suffixesBs = (\x -> "+" <> foldedCase x) <$> suffixes mediaType
      paramsBs = Map.foldlWithKey' (\acc k v -> acc <> "; " <> foldedCase k <> "=" <> v) "" $ parameters mediaType
  in mainTypeBs <> "/" <> subTypeBs <> B.concat suffixesBs <> paramsBs
  where 
    mainTypeAsByteString Text        = "text"
    mainTypeAsByteString Image       = "image"
    mainTypeAsByteString Audio       = "audio"
    mainTypeAsByteString Video       = "video"
    mainTypeAsByteString Application = "application"
    mainTypeAsByteString Multipart   = "multipart"
    mainTypeAsByteString (Other x)   = x

-- | Parse a Media Type from an ASCII ByteString
parseMediaType :: MonadThrow m => B.ByteString -> m MediaType
parseMediaType bs = either (throw . MediaTypeException . T.pack) return $ A.parseOnly pMediaType bs

-- | The @application/json@ Media Type
applicationJson :: MediaType
applicationJson = MediaType 
  { mainType = Application
  , subType = mk "json"
  , suffixes = []
  , parameters = Map.empty
  }

-- | The @application/x-www-form-urlencoded@ Media Type
applicationXWWWFormUrlEncoded :: MediaType
applicationXWWWFormUrlEncoded = MediaType 
  { mainType = Application
  , subType = mk "x-www-form-urlencoded"
  , suffixes = []
  , parameters = Map.empty
  }

-- | The @text/html@ Media Type
textHtml :: MediaType
textHtml = MediaType 
  { mainType = Text
  , subType = mk "html"
  , suffixes = []
  , parameters = Map.empty
  }

pContentType :: A.Parser ContentType
pContentType = 
  convertContentType . mk <$> A.takeWhile1 isAsciiAlpha
  where 
    convertContentType :: CI B.ByteString -> ContentType
    convertContentType "text"        = Text
    convertContentType "image"       = Image
    convertContentType "audio"       = Audio
    convertContentType "video"       = Video
    convertContentType "application" = Application
    convertContentType "multipart"   = Multipart
    convertContentType x             = Other x

pSubType :: A.Parser (CI B.ByteString)
pSubType = mk <$> A.takeWhile1 isSubtypeChar

pSuffix :: A.Parser (CI B.ByteString)
pSuffix = mk <$> A.takeWhile1 isAsciiAlpha

pMediaType :: A.Parser MediaType
pMediaType = do
  mainType' <- pContentType
  _ <- A.char '/'
  subType' <- pSubType
  suffixes' <- pSuffix `A.sepBy` A.char '+'
  parameters' <- A.many' (A.char ';' *> A.skipSpace *> pParam)
  return $ MediaType { mainType = mainType', subType = subType', suffixes = suffixes', parameters = Map.fromList parameters'}

-- | Checks whether a char is ascii & alpha
isAsciiAlpha :: Char -> Bool
isAsciiAlpha c = C.isAlpha c && C.isAscii c

isSpecial :: Char -> Bool
isSpecial c = c == '(' || c == ')' || c == '<' || c == '>' || c == '@' || c == ',' || c == ':' || c == ';' || c == '\\' || c == '"' || c == '/' || c == '[' || c == ']' || c == '?' || c == '='

isTokenChar :: Char -> Bool
isTokenChar c = (not $ isSpecial c) && (not $ C.isSpace c) && C.isAscii c && (not $ C.isControl c)

isQuotedChar :: Char -> Bool
isQuotedChar c = C.isAscii c && (not $ C.isControl c)

isSubtypeChar :: Char -> Bool
isSubtypeChar c = (isTokenChar c) && (c /= '+')

pTokens :: A.Parser B.ByteString
pTokens = A.takeWhile1 isTokenChar

pQuotedString :: A.Parser B.ByteString
pQuotedString = A.char '"' *> A.takeWhile isQuotedChar <* A.char '"'

pParam :: A.Parser (CI B.ByteString, B.ByteString)
pParam = do
  attribute <- pTokens
  _ <- A.char '='
  value <- pTokens <|> pQuotedString
  return (mk attribute, value)


