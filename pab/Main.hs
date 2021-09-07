{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE RankNTypes         #-}
{-# LANGUAGE TypeApplications   #-}
{-# LANGUAGE TypeFamilies       #-}
{-# LANGUAGE TypeOperators      #-}
{-# LANGUAGE ScopedTypeVariables      #-}
{-# LANGUAGE RecursiveDo     #-}
module Main
    ( main
    ) where

import           Control.Monad                           (forM, forM_, void, when)
import           Control.Monad.Freer                     (Eff, Member, interpret, type (~>))
import           Control.Monad.Freer.Error               (Error)
import           Control.Monad.Freer.Extras.Log          (LogMsg)
import           Control.Monad.IO.Class                  (MonadIO (..))
import           Data.Aeson                              (FromJSON, Result (..), ToJSON, encode, fromJSON)
import           Data.Default
import qualified Data.Map.Strict                         as Map
import qualified Data.Monoid                             as Monoid
import qualified Data.Semigroup                          as Semigroup
import           Data.Text                               (Text)
import           Data.Text.Prettyprint.Doc               (Pretty (..), viaShow)
import           GHC.Generics                            (Generic)
import           Ledger
import           Ledger.Ada                              (adaSymbol, adaToken)
import           Ledger.Constraints
import qualified Ledger.Value                            as Value
import           Plutus.Contract                         hiding (when)
import qualified Plutus.Contracts.Currency               as Currency
import qualified Plutus.Contracts.Uniswap                as Uniswap
import           Plutus.PAB.Effects.Contract             (ContractEffect (..))
import           Plutus.PAB.Effects.Contract.Builtin     (Builtin, SomeBuiltin (..), type (.\\))
import qualified Plutus.PAB.Effects.Contract.Builtin     as Builtin
import           Plutus.PAB.Monitoring.PABLogMsg         (PABMultiAgentMsg)
import           Plutus.PAB.Simulator                    (SimulatorEffectHandlers, logString)
import qualified Plutus.PAB.Simulator                    as Simulator
import           Plutus.PAB.Types                        (PABError (..))
import qualified Plutus.PAB.Webserver.Server             as PAB.Server
import           Prelude                                 hiding (init)
import           Wallet.Emulator.Types                   (Wallet (..), walletPubKey)
import           Wallet.Types ()

main :: IO ()
main = mdo
  uniswapServerHandle <- Simulator.runSimulationWith handlers $ do
    logString @(Builtin UniswapContracts) "Starting Uniswap PAB webserver on port 9080. Press enter to exit."
    shutdown <- PAB.Server.startServerDebug

    -- IHS Notes: creates 1 million token for the smart contract exchange
    cidInit  :: ContractInstanceId <- Simulator.activateContract (Wallet 1) Init
    cs       <- flip Simulator.waitForState cidInit $ \json -> case fromJSON json of
                    Success (Just (Semigroup.Last cur)) -> Just $ Currency.currencySymbol cur
                    _                                   -> Nothing
    _        <- Simulator.waitUntilFinished cidInit

    logString @(Builtin UniswapContracts) $ "Initialization finished. Minted: " ++ show cs

    let pokeDexTokens = ["PikaCoin", "BulbaCoin", "CharmaCoin", "DiggleCoin"]
        coins = Map.fromList [(tn, Uniswap.mkCoin cs tn) | tn <- pokeDexTokens]
        ada   = Uniswap.mkCoin adaSymbol adaToken

    -- IHS Notes: Creates a Smart Contract that will contain swappable tokens
    cidStart :: ContractInstanceId <- Simulator.activateContract (Wallet 1) UniswapStart
    us :: Uniswap.Uniswap <- flip Simulator.waitForState cidStart $ \json -> case (fromJSON json :: Result (Monoid.Last (Either Text Uniswap.Uniswap))) of
                    Success (Monoid.Last (Just (Right us))) -> Just us
                    _                                       -> Nothing
    logString @(Builtin UniswapContracts) $ "Uniswap instance created: " ++ show us ++ " Contract Instance ID: " ++ show cidStart

    cids :: Map.Map Wallet ContractInstanceId <- fmap Map.fromList $ forM wallets $ \w -> do
        cid <- Simulator.activateContract w $ UniswapUser us
        logString @(Builtin UniswapContracts) $ "Uniswap user contract started for " ++ show w
        -- Simulator.waitForEndpoint cid "funds"
        -- _ <- Simulator.callEndpointOnInstance cid "funds" ()
        -- v <- flip Simulator.waitForState cid $ \json -> case (fromJSON json :: Result (Monoid.Last (Either Text Uniswap.UserContractState))) of
        --         Success (Monoid.Last (Just (Right (Uniswap.Funds v)))) -> Just v
        --         _                                                      -> Nothing
        -- logString @(Builtin UniswapContracts) $ "initial funds in wallet " ++ show w ++ ": " ++ show v
        return (w, cid)

    -- IHS Notes: Creates a new liquidity pool for ADA and "A" Coin | 100k for ADA and 500k for "A" Coin
    let cp = Uniswap.CreateParams ada (coins Map.! "PikaCoin") 100000 500000
        cp2 = Uniswap.CreateParams ada (coins Map.! "BulbaCoin") 100000 500000
    logString @(Builtin UniswapContracts) $ "creating liquidity pool: " ++ show (encode cp)
    -- IHS Notes: How to send request to smart contract instances with API call and values, only return Maybe Error
    let cid2 = cids Map.! Wallet 2
    Simulator.waitForEndpoint cid2 "create"
    _  <- Simulator.callEndpointOnInstance cid2 "create" cp
    -- IHS: use waitForState to wait for the smart contract response
    flip Simulator.waitForState (cids Map.! Wallet 2) $ \json -> case (fromJSON json :: Result (Monoid.Last (Either Text Uniswap.UserContractState))) of
        Success (Monoid.Last (Just (Right Uniswap.Created))) -> Just ()
        _                                                    -> Nothing
    logString @(Builtin UniswapContracts) "liquidity pool created"

    Simulator.waitForEndpoint cid2 "create"
    _  <- Simulator.callEndpointOnInstance cid2 "create" cp2
    -- IHS: use waitForState to wait for the smart contract response
    flip Simulator.waitForState (cids Map.! Wallet 2) $ \json -> case (fromJSON json :: Result (Monoid.Last (Either Text Uniswap.UserContractState))) of
        Success (Monoid.Last (Just (Right Uniswap.Created))) -> Just ()
        _                                                    -> Nothing
    logString @(Builtin UniswapContracts) "second liquidity pool created"

    -- IHS Notes: Checking balances before pressing ENTER in ghci while running main
    bal1 <- Simulator.currentBalances
    Simulator.logBalances @(Builtin UniswapContracts) bal1

    -- IHS Notes: Mock chain is now in a listening state.
    -- Calls made to http://localhost:9080/api/contract/instance/5e9de181-d3a2-4116-b957-33f59b13c7c8/endpoint/funds
    -- or any other action, .../endpoint/{action}, will have to be followed with a call to
    -- http://localhost:9080/api/contract/instance/{ContractInstanceId}/status in order to get the
    -- response from the `observableState` field
    _ <- liftIO getLine

    -- IHS Notes: Checking balances before pressing ENTER in ghci while running main
    bal <- Simulator.currentBalances
    Simulator.logBalances @(Builtin UniswapContracts) bal

    return (shutdown, Just us)
  case uniswapServerHandle of
    Left _ -> return ()
    Right (shutdown', Nothing) -> void $ Simulator.runSimulationWith handlers $ do
      logString @(Builtin UniswapContracts) "Hit Right(_, Nothing) case"
      shutdown'
    Right (shutdown', mUs) -> void $ Simulator.runSimulationWith handlers $ do
      logString @(Builtin UniswapContracts) "Hit Right(_, Just ...) case"
      _ <- liftIO getLine
      shutdown'

data UniswapContracts =
      Init
    | UniswapStart
    | UniswapUser Uniswap.Uniswap
    deriving (Eq, Ord, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

instance Pretty UniswapContracts where
    pretty = viaShow

instance Builtin.HasDefinitions UniswapContracts where
    getDefinitions = [Init, UniswapStart]
    getSchema = \case
        UniswapUser _ -> Builtin.endpointsToSchemas @Uniswap.UniswapUserSchema
        UniswapStart  -> Builtin.endpointsToSchemas @Uniswap.UniswapOwnerSchema
        Init          -> Builtin.endpointsToSchemas @Empty
    getContract = \case
        UniswapUser us -> SomeBuiltin . awaitPromise $ Uniswap.userEndpoints us
        UniswapStart   -> SomeBuiltin Uniswap.ownerEndpoint
        Init           -> SomeBuiltin initContract'

handlers :: SimulatorEffectHandlers (Builtin UniswapContracts)
handlers =
    Simulator.mkSimulatorHandlers def def
    $ interpret (Builtin.contractHandler (Builtin.handleBuiltin @UniswapContracts))

wallets :: [Wallet]
wallets = [Wallet i | i <- [1 .. 4]]

initContract' :: Contract (Maybe (Semigroup.Last Currency.OneShotCurrency)) Currency.CurrencySchema Currency.CurrencyError ()
initContract' = do
    let pokeDexTokens = ["PikaCoin", "BulbaCoin", "CharmaCoin", "DiggleCoin"]
    ownPK <- pubKeyHash <$> ownPubKey
    cur   <- Currency.mintContract ownPK [(tn, fromIntegral (length wallets) * amount) | tn <- pokeDexTokens]
    let cs = Currency.currencySymbol cur
        v  = mconcat [Value.singleton cs tn amount | tn <- pokeDexTokens]
    forM_ wallets $ \w -> do
        let pkh = pubKeyHash $ walletPubKey w
        when (pkh /= ownPK) $ do
            tx <- submitTx $ mustPayToPubKey pkh v
            awaitTxConfirmed $ txId tx
    tell $ Just $ Semigroup.Last cur
  where
    amount = 1000000

