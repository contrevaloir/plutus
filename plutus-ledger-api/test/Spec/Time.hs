{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fno-warn-incomplete-uni-patterns #-}

module Spec.Time where

import Data.Aeson (decode, encode)
import Plutus.V1.Ledger.Time

import Hedgehog (Property, forAll, property)
import Hedgehog qualified
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

invPropJson :: Property
invPropJson = property $ do
  t <- forAll $ Gen.integral (fromIntegral <$> Range.linearBounded @Int)
  let posixTime = POSIXTime t
  Hedgehog.tripping posixTime encode decode

tests :: TestTree
tests =
  testGroup
    "plutus-ledger-api-time"
    [ testProperty "POSIXTime FromJSON/ToJSON inverse property" invPropJson
    ]
