{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE DataKinds #-}

module Dormouse.UriSpec
  ( tests
  ) where

import Test.Hspec
import Dormouse.Uri
import Dormouse.Uri.QQ
import qualified Network.HTTP.Client as C

tests :: IO()
tests = hspec $ 
  describe "parseURI" $ do
    it "generates a non-secure request for an http uri" $ do
      req <- parseRequestFromUri [http|http://google.com|]
      C.secure req `shouldBe` False
    it "generates a secure request for an https uri" $ do
      req <- parseRequestFromUri [https|https://google.com|]
      C.secure req `shouldBe` True
    it "generates a non-secure request with the correct host" $ do
      req <- parseRequestFromUri [http|http://google.com|]
      C.host req `shouldBe` "google.com"
    it "generates a request on port 80 for an http uri with no provided port" $ do
      req <- parseRequestFromUri [http|http://google.com|]
      C.port req `shouldBe` 80
    it "generates a request on the supplied port for an http uri with a provided port" $ do
      req <- parseRequestFromUri [http|http://google.com:8080|]
      C.port req `shouldBe` 8080
    it "generates a request on port 443 for an https uri with no provided port" $ do
      req <- parseRequestFromUri [https|https://google.com|]
      C.port req `shouldBe` 443
    it "generates a request on the supplied port for an https uri with a provided port" $ do
      req <- parseRequestFromUri [https|https://google.com:8443|]
      C.port req `shouldBe` 8443
    it "generates a request with the correct path (simple)" $ do
      req <- parseRequestFromUri [https|https://google.com/my/path/is/great|]
      C.path req `shouldBe` "/my/path/is/great"
    it "generates a request with the correct path (unicode)" $ do
      req <- parseRequestFromUri [https|https://google.com/my/path/is/great%F0%9F%98%88|]
      C.path req `shouldBe` "/my/path/is/great%F0%9F%98%88"
    it "generates a request with the correct query params (simple)" $ do
      req <- parseRequestFromUri [https|https://google.com?test=abc|]
      C.queryString req `shouldBe` "?test=abc"
    it "generates a request with the correct query params (unicode)" $ do
      req <- parseRequestFromUri [https|https://google.com?test=%F0%9F%98%80|]
      C.queryString req `shouldBe` "?test=%F0%9F%98%80"
