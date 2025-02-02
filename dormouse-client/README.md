# Dormouse-Client

Dormouse is an HTTP client that will help you REST.

It was designed with the following objectives in mind:
       
  - HTTP requests and responses should be modelled by a simple, immutable Haskell Record.
  - Real HTTP calls should be made via an abstraction layer (`MonadDormouseClient`) so testing and mocking is painless.
  - Illegal requests should be unrepresentable, such as HTTP GET requests with a content body.
  - It should be possible to enforce a protocol (e.g. https) at the type level.
  - It should be possible to handle large request and response bodies via constant memory streaming.

Example use:

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

import Control.Monad.IO.Class
import Data.Aeson.TH 
import Dormouse.Client
import GHC.Generics (Generic)
import Dormouse.Url.QQ

data UserDetails = UserDetails 
  { name :: String
  , nickname :: String
  , email :: String
  } deriving (Eq, Show, Generic)

deriveJSON defaultOptions ''UserDetails

data EchoedJson a = EchoedJson 
  { echoedjson :: a
  } deriving (Eq, Show, Generic)

deriveJSON defaultOptions {fieldLabelModifier = drop 6} ''EchoedJson

main :: IO ()
main = do
  manager <- newManager tlsManagerSettings
  runDormouseClient (DormouseClientConfig { clientManager = manager }) $ do
    let 
      userDetails = UserDetails 
        { name = "James T. Kirk"
        , nickname = "Jim"
        , email = "james.t.kirk@starfleet.com"
        }
      req = accept json $ supplyBody json userDetails $ post [https|https://postman-echo.com/post|]
    response :: HttpResponse (EchoedJson UserDetails) <- expect req
    liftIO $ print response
    return ()
```

## Building requests

### GET requests

Building a GET request is simple using a `Url` (Please see the [Dormouse-Uri](../dormouse-uri/README.md) documentation for more details of how to safely create and construct `Url`s).

```haskell
postmanEchoGetUrl :: Url "http"
postmanEchoGetUrl = [http|http://postman-echo.com/get?foo1=bar1&foo2=bar2/|]

postmanEchoGetReq :: HttpRequest (Url "http") "GET" Empty EmptyPayload acceptTag
postmanEchoGetReq = get postmanEchoGetUrl
```

It is often useful to tell Dormouse about the expected `Content-Type` of the response in advance so that the correct `Accept` headers can be sent:

```haskell
postmanEchoGetReq' :: HttpRequest (Url "http") "GET" Empty EmptyPayload acceptTag
postmanEchoGetReq' = accept json $ get postmanEchoGetUrl
```

### POST requests

You can build POST requests in the same way

```haskell
postmanEchoPostUrl :: Url "https"
postmanEchoPostUrl = [https|https://postman-echo.com/post|]

postmanEchoPostReq :: HttpRequest (Url "https") "POST" Empty EmptyPayload JsonPayload
postmanEchoPostReq = accept json $ post postmanEchoPostUrl
```

## Expecting a response

Since we're expecting json, we also need data types and `FromJSON` instances to interpret the response with.  Let's start with an example to handle the GET request.

```haskell
{-# LANGUAGE DeriveGeneric #-}
```

```haskell
data Args = Args 
  { foo1 :: String
  , foo2 :: String
  } deriving (Eq, Show, Generic)

data PostmanEchoResponse = PostmanEchoResponse
  { args :: Args
  } deriving (Eq, Show, Generic)
```


Once the request has been built, you can send it and expect a response of a particular type in any `MonadDormouseClient m`.

```haskell
sendPostmanEchoGetReq :: MonadDormouseClient m => m PostmanEchoResponse
sendPostmanEchoGetReq = do
  (resp :: HttpResponse PostmanEchoResponse) <- expect postmanEchoGetReq'
  return $ responseBody resp
```

## Running Dormouse

Dormouse is not opinionated about how you run it.  

You can use a concrete type.

```haskell
main :: IO ()
main = do
  manager <- newManager tlsManagerSettings
  postmanResponse <- runDormouseClient (DormouseClientConfig { clientManager = manager }) sendPostmanEchoGetReq
  print postmanResponse
```

You can integrate the `DormouseClientT` Monad Transformer into your transformer stack.

```haskell
main :: IO ()
main = do
  manager <- newManager tlsManagerSettings
  postmanResponse <- runDormouseClientT (DormouseClientConfig { clientManager = manager }) sendPostmanEchoGetReq
  print postmanResponse
```

You can also integrate into your own Application monad using the `sendHttp` function from `Dormouse.Client.MonadIOImpl` and by providing an instance of `HasDormouseConfig` for your application environment.

```haskell
data MyEnv = MyEnv 
  { dormouseEnv :: DormouseClientConfig
  }

instance HasDormouseClientConfigMyEnv where
  getDormouseClientConfig = dormouseEnv

newtype AppM a = AppM
  { unAppM :: ReaderT Env IO a 
  } deriving (Functor, Applicative, Monad, MonadReader Env, MonadIO, MonadThrow)

instance MonadDormouseClient (AppM) where
  send = IOImpl.sendHttp

runAppM :: Env -> AppM a -> IO a
runAppM deps app = flip runReaderT deps $ unAppM app
```
