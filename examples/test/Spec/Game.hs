{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TemplateHaskell  #-}
{-# LANGUAGE TypeApplications #-}

module Spec.Game
    ( tests
    ) where

import           Control.Monad         (void)
import           Ledger.Ada            (adaValueOf, lovelaceValueOf)
import           Plutus.Contract       (Contract, ContractError)
import           Plutus.Contract.Test
import           Plutus.Contracts.Game
import           Plutus.Trace.Emulator (ContractInstanceTag)
import qualified Plutus.Trace.Emulator as Trace
import qualified PlutusTx
import qualified PlutusTx.Prelude      as PlutusTx
import           Test.Tasty
import qualified Test.Tasty.HUnit      as HUnit
import Prelude hiding (not)

w1, w2 :: Wallet
w1 = Wallet 1
w2 = Wallet 2

t1, t2 :: ContractInstanceTag
t1 = Trace.walletInstanceTag w1
t2 = Trace.walletInstanceTag w2

theContract :: Contract () GameSchema ContractError ()
theContract = game

-- W1 locks funds, W2 (and other wallets) should have access to guess endpoint
-- No funds locked, so W2 (and other wallets) should not have access to guess endpoint
tests :: TestTree
tests = testGroup "game"
    [ checkPredicate "Expose 'lock' endpoint, but not 'guess' endpoint"
        (endpointAvailable @"lock" theContract (Trace.walletInstanceTag w1)
          .&&. not (endpointAvailable @"guess" theContract (Trace.walletInstanceTag w1)))
        $ void $ Trace.activateContractWallet w1 (lock @ContractError)

    , checkPredicate "'lock' endpoint submits a transaction"
        (anyTx theContract (Trace.walletInstanceTag w1))
        $ do
            hdl <- Trace.activateContractWallet w1 theContract
            Trace.callEndpoint @"lock" hdl (LockParams "secret" (adaValueOf 10))

    , checkPredicate "'guess' endpoint is available after locking funds"
        (endpointAvailable @"guess" theContract (Trace.walletInstanceTag w2))
        $ do
          void $ Trace.activateContractWallet w2 theContract
          lockTrace "secret"

    , checkPredicate "guess right (unlock funds)"
        (walletFundsChange w2 (1 `timesFeeAdjust` 10)
          .&&. walletFundsChange w1 (1 `timesFeeAdjust` (-10)))
        $ do
          void $ Trace.waitNSlots 1
          hdlLock <- Trace.activateContractWallet w1 (lock @ContractError)
          void $ Trace.waitNSlots 1
          Trace.callEndpoint @"lock" hdlLock (LockParams "secret" (lovelaceValueOf 10))
          void $ Trace.waitNSlots 1

          hdlGuess <- Trace.activateContractWallet w2 (guess @ContractError)
          Trace.callEndpoint @"guess" hdlGuess (GuessParams "secret")
          void $ Trace.waitNSlots 1

          -- lockTrace "secret"
          -- guessTrace "secret"

    , checkPredicate "guess wrong"
        (walletFundsChange w2 PlutusTx.zero
          .&&. walletFundsChange w1 (1 `timesFeeAdjust` (-10)))
        $ do
          lockTrace "secret"
          guessTrace "SECRET"

    , goldenPir "examples/test/Spec/game.pir" $$(PlutusTx.compile [|| validateGuess ||])

    , HUnit.testCase "script size is reasonable" (reasonable gameValidator 20000)
    ]
