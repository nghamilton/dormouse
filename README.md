## Dormouse

Dormouse is a set of libraries designed to permit productive, type-safe, HTTP in Haskell.  It currently consists of:

 - [Dormouse-Uri](dormouse-uri/README.md), a library for type-safe representations of `Url`s and `Uri`s.
 - [Dormouse-Client](dormouse-client/README.md), a simple, type-safe and testable HTTP client.

Quick example:

```haskell
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE DataKinds #-}

import Control.Monad.IO.Class
import Dormouse.Client
import Data.Aeson.TH 
import Dormouse.Url.QQ

data UserDetails = UserDetails 
  { name :: String
  , nickname :: String
  , email :: String
  } deriving (Eq, Show)

deriveJSON defaultOptions ''UserDetails

data EchoedJson a = EchoedJson 
  { echoedjson :: a
  } deriving (Eq, Show)

deriveJSON defaultOptions {fieldLabelModifier = drop 6} ''EchoedJson

main :: IO ()
main = do
  manager <- newManager tlsManagerSettings
  runDormouse (DormouseClientConfig{ clientManager = manager }) $ do
    let userDetails = UserDetails { name = "James T. Kirk", nickname = "Jim", email = "james.t.kirk@starfleet.com"}
    let req = accept json $ supplyBody json userDetails $ post [https|https://postman-echo.com/post|]
    response :: HttpResponse (EchoedJson UserDetails) <- expect req
    liftIO $ print response
    return ()
```


