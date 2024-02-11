# Centry<br>
Centry is decentralised perpetual trading platform that is powered by the Request For Quote (R.F.Q)model to ensure great price discovery and thereby trades are executed with __0__ Slippage and M.E.V resistance.

__The Request for Quote(R.F.Q)__ model is the  most capital efficient model of price discovery that is comprised of liquidity providers,who can provide liquidty to just one asset by setting Quotes.
A __Quote__ here is an offer by anyone to take the other end of a trade for a certain premium discount that is known before trade,that is the persosn is willing to take the other end of the trade and as an incentive,they are offerd a premium .
>Assuming a trader wants to buy BTC with $USD and the price of BTC is at $35,000 ,a liquidity  might set a quote to take the other end of the trade for a premium of 0.02 percent that is the liquidity provider is accepting to take that offer at a price that is 0.02 percent higher than the current price <br>
> i.e liquidty provider would sell at a rate of <br> 
__current BTC price + 0.02 % of current BTC price__.<br>

Centry utilises this model to ensure capital eficient trades with zero slippage and best price discovery by enabling the trader to settle their trades with any quote of their choice provided by a liquidity provider 



## Unique Features of Centry<br>
 * ### Decentralised Leverage Mechanism<br>
   Centry operates with a decentralised levarage model through the use of third party pools which allow traders to borrow capital to take a position .These pools set pre defined conditions such as 
   * The assets that can be traded for the asset being borrowed
   *  The minimum capital that traders need to put up as collateral
   *  The maximum debt a trader can take to trade a particular asset.<br>
   
   These pools work in a decentralised manner and is not controlled by Centry .

* ### Request For Quote(R.F.Q)<br>
  The R.F.Q model provides the convenience,capital efficeincy and price discovery offered by a traditional Centralised Exchange OrderBook and  also the inherent transparency and decentralization offered by a Decentralised Exchange.

* ### Efficient Price data Availabilty <br>
  Centry uses a Price Feed Canister  that utilises the [XRC](https://internetcomputer.org/docs/current/developer-docs/integrations/exchange-rate/exchange-rate-canister) built by DFINITY which uses HTTP outcalls to get accurate and timely price data for settling trades,thereby greatly improving trade excution speed . <br>


  ### To deploy canisters <br>
  ```bash
     #start your local replica
   
   dfx start --background

     #create an empty canister for Main and get the canisterID
    dfx canister create --network ic Main
   
    export mainID=$(dfx canister id --network ic Main)

  
  ```
     deploy priceFeed and gets its canister id 
     ```bash

    dfx deploy --network ic PriceFeed --argument "(principal \"uf6dk-hyaaa-aaaaq-qaaaq-cai\")"
    
    export priceFeedID=$(dfx canister id --network ic PriceFeed)
     
     ```

     deploy the ClearingHouse canister and get its id
  ```bash
       #deploy the clearingHouse canister

    dfx deploy --network ic ClearingHouse --argument "(principal \"${mainID}\",principal \"${priceFeedID}\")" ;

    export clearingHouseID=$(dfx canister id --network ic ClearingHouse) 

  ``` 

    finally deploy the code of the main canister on the network 
  ```bash
      dfx deploy --network ic Main --argument "(principal \"${clearingHouseID}\",principal \"${priceFeedID}\")"
  ```

  * [Main](#link)<br>
  * [PriceFeed](#link)<br>
  * [ClearingHouse](#link)

