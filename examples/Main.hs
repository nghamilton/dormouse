{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE DeriveGeneric #-}

import Control.Monad.IO.Class
import Dormouse
import Data.Aeson.TH
import GHC.Generics (Generic)
import URI.ByteString.QQ (uri)
import Web.FormUrlEncoded (ToForm(..), FromForm(..))

data UserDetails = UserDetails 
  { name :: String
  , nickname :: String
  , email :: String
  } deriving (Eq, Show, Generic)

deriveJSON defaultOptions ''UserDetails
instance ToForm UserDetails
instance FromForm UserDetails

data EchoedJson a = EchoedJson 
  { echoedjson :: a
  } deriving (Eq, Show, Generic)

deriveJSON defaultOptions {fieldLabelModifier = drop 6} ''EchoedJson

data EchoedForm a = EchoedForm 
  { echoedform :: a
  } deriving (Eq, Show, Generic)

deriveJSON defaultOptions {fieldLabelModifier = drop 6} ''EchoedForm

main :: IO ()
main = do
  manager <- newManager tlsManagerSettings
  runDormouse (DormouseConfig { clientManager = manager }) $ do
    let userDetails = UserDetails { name = "James T. Kirk", nickname = "Jim", email = "james.t.kirk@starfleet.com"}
    let req = accept json $ supplyBody json userDetails $ post [uri|https://postman-echo.com/post?ship=enterprise|]
    let req' = accept json $ supplyBody urlForm userDetails $ post [uri|https://postman-echo.com/post?ship=enterprise|]
    resp <- send req
    (response :: EchoedJson UserDetails) <- decodeBody resp
    liftIO $ print response
    resp' <- send req'
    (response' :: EchoedForm UserDetails) <- decodeBody resp'
    liftIO $ print response'
    return ()
