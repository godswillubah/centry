import Nat32 "mo:base/Nat32";
import Error "mo:base/Error";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Int "mo:base/Int";

import ICRC "Interface/ICRC";
import XRC "Interface/XRC";

import Main "main";
import Types "Types";
import Pool "Pool";
import PriceFeed "PriceFeed";

actor class ClearingHouse(mainPrincipal : Principal, _priceFeed : Principal) = {
    type ExchangeRate = XRC.ExchangeRate;

    type Token = ICRC.Token;

    type Asset = Types.Asset;

    type TokenDetails = Types.TokenDetails;

    type Quote = Types.Quote;

    type Pool = Pool.Pool;

    type OpenPositionParams = Types.OpenPositionParams;

    type ClosePositionParams = Types.ClosePositionParams;

    type Position = Types.Position;

    stable let main : Main.Main = actor (Principal.toText(mainPrincipal));
    stable let priceFeed : PriceFeed.PriceFeed = actor (Principal.toText(_priceFeed));

    stable let percentage_basis = Nat64.pow(10, 6);
    //gets the y percent of x where y is the intended percentage *  100_000 ,
    private func _percent(x : Nat, y : Nat) : Nat {
        // product must be divided by 100_000 since y is multiple of 100_000
        return (x * y) / Nat64.toNat(percentage_basis);
    };

    /*calculates the margin fee given the start time ,the current time ,the amount and the fee in percent

      ``margin fees are paid for every hour spent on the trade

      ``marginfees will be paid even if trade duration is not up to an hour
      */
    private func calculateMarginFee(starttime : Int, current_time : Int, amount : Nat, fee : Nat) : Nat {
        let duration : Int = current_time - starttime;
        let interval : Int = switch (duration / 3600 >= 1) {
            case (true) { duration / 3600 };
            case (false) { 1 };
        };
        var fee = 0;
        let counter = 0;
        while (counter < interval) {
            fee := amount - _percent(amount, fee);
        };

        return fee;
    };

    /*
      used for checking if x falls in the range of min to max included
      liquidity providers set range in the amount of the asset they are willing to receive such that they can not exceed certain amount
    */
    private func inRange(x : Nat, min : Nat, max : Nat) : Bool {
        return (x <= max and x >= min);
    };

    private func sendOut(_tokenPrincipal : Principal, amount : Nat, from : Principal, from_subaccount : ?Blob, to : Principal, to_subaccount : ?Blob) : async Nat {

        let token : Token = actor (Principal.toText(_tokenPrincipal));
        let fee = await token.icrc1_fee();
        let tx = await token.icrc2_transfer_from({
            spender_subaccount = null;
            from = { owner = from; subaccount = from_subaccount };
            to = { owner = to; subaccount = to_subaccount };
            amount = amount;
            fee = ?fee;
            memo = null;
            created_at_time = null;
        });
        let result = switch (tx) {
            case (#Ok(num)) { return num };
            case (#Err(err)) { throw Error.reject("Token send out failed") };
        };
    };

    private func sendIn(_tokenPrincipal : Principal, amount : Nat, to : Principal, subaccount : ?Blob) : async Nat {
        let token : Token = actor (Principal.toText(_tokenPrincipal));

        let fee = await token.icrc1_fee();
        let tx = await token.icrc2_transfer_from({
            spender_subaccount = null;
            from = { owner = mainPrincipal; subaccount = null };
            to = { owner = to; subaccount = subaccount };
            amount = amount;
            fee = ?fee;
            memo = null;
            created_at_time = null;
        });
        let result = switch (tx) {
            case (#Ok(num)) { return num };
            case (#Err(err)) { throw Error.reject("Token send in Failed") };
        };

    };

    /* takes position paramters and checks if all conditions are satisfied

  `` Returns true if tthey are satisfied or false for any error
  */
    private func isOpenPositionValid(params : OpenPositionParams) : async {
        valid : Bool;
        margin_fee : Nat64;
    } {
        let quote = await main.getQuote(params.base_asset.id, params.quote_id);
        let pool_principal = await main.getPool(params.pool_id);
        let pool : Pool.Pool = actor (Principal.toText(pool_principal));

        //gets the token details associated with that token in the pool provifding the leverage
        let token_details = await pool.getTokenDetails(params.base_asset.id);

        return {
            valid = token_details.is_allowed // checks if token is an allowed asset by the pool providing levarage

            //checks that maximum debt for trading that token is not exceed
            and params.debt <= token_details.max_debt and params.collateral_amount >= token_details.min_collateral and inRange(Nat64.toNat(params.debt), Nat64.toNat(quote.range.min), Nat64.toNat(quote.range.max));

            // returns margin fee
            margin_fee = token_details.margin_fee;
        };

    };

    private func isClosePositionValid(caller : Principal, params : ClosePositionParams) : async Bool {
        let position : Position = await main.getPositionByID(params.quote_asset.id, params.position_id);
        let quote : Quote = await main.getQuote(position.asset_In.id, params.quote_id);
        let pool : Pool = actor (Principal.toText(position.debt_pool));
        let allowed = caller == position.owner or (await pool.isLiquidator(caller));

        return (inRange(position.amount_in, Nat64.toNat(quote.range.min), Nat64.toNat(quote.range.max)) and allowed and quote.quote_asset.id == position.asset_out.id);
    };

    private func _openPosition(caller : Principal, params : OpenPositionParams, subaccount : ?Blob, marginFee : Nat64) : async () {

        let pool_principal : Principal = await main.getPool(params.pool_id);

        let quote : Quote = await main.getQuote(params.base_asset.id, params.quote_id);

        //gets the current price rate based from the priceFeed contract
        let current_rate : ExchangeRate = await priceFeed.get_exchange_rate({
            base_asset = {
                symbol = params.base_asset.symbol;
                class_ = params.base_asset.class_;
            };
            quote_asset = {
                symbol = quote.quote_asset.symbol;
                class_ = quote.quote_asset.class_;
            };
            timestamp = null;
        });

        //converst the picedecimal to Nat64 for calculation

        let price_decimal : Nat64 = Nat32.toNat64(current_rate.metadata.decimals);
        // calculate the equivalent amount of base_asset equalin value to the quote asset amount
        let exchange_value : Nat64 = (params.debt * current_rate.rate) / 10 ** price_decimal;

        //the value of quote
        let quote_value : Nat = _percent(Nat64.toNat(exchange_value), Nat64.toNat(quote.offer));

        //get the canister id of the debt_pool
        let debt_pool : Principal = await main.getPool(params.pool_id);

        // token transactions

        //transfer collateral in from caller(trader)
        let collateral_in : Nat = await sendIn(quote.quote_asset.id, Nat64.toNat(params.collateral_amount), caller, subaccount);

        //transfer in the quote value from the quote liquidity provider
        let provided_Liquidity : Nat = await sendIn(quote.quote_asset.id, quote_value, quote.liq_provider_id, null);

        //transfer in the debt amount from
        let debt_in : Nat = await sendOut(params.base_asset.id, Nat64.toNat(params.debt), debt_pool, null, pool_principal : Principal, null);

        let position : Position = {
            amount_in = collateral_in + provided_Liquidity;
            asset_In = params.base_asset;
            asset_out = quote.quote_asset;
            debt = params.debt;
            debt_pool = debt_pool;
            marginFee = marginFee;
            timestamp = Time.now();
            owner = caller;
        };

        //store position
        await main.storePosition(params.base_asset.id, position, caller);
        //remove Quote
        await main.removeQuote(params.base_asset.id, params.quote_id);
    };

    private func _closePosition(caller : Principal, params : ClosePositionParams) : async () {
        let position : Position = await main.getPositionByID(params.quote_asset.id, params.position_id);
        let quote : Quote = await main.getQuote(position.asset_In.id, params.quote_id);

        let current_rate : ExchangeRate = await priceFeed.get_exchange_rate({
            base_asset = {
                symbol = position.asset_out.symbol;
                class_ = position.asset_out.class_;
            };
            quote_asset = {
                symbol = position.asset_In.symbol;
                class_ = position.asset_In.class_;
            };
            timestamp = null;
        });
        let price_decimal : Nat = Nat32.toNat(current_rate.metadata.decimals);

        let equivalent = position.amount_in * Nat64.toNat(current_rate.rate) / 10 ** price_decimal;

        let quote_value = _percent(equivalent, Nat64.toNat(quote.offer));
        let current_time = Time.now();
        let fee = calculateMarginFee(current_time, position.timestamp, Nat64.toNat(position.debt), Nat64.toNat(position.marginFee));

        let provided_Liquidity = await sendIn(position.asset_out.id, quote_value, quote.liq_provider_id, null);
        let amount_sent_out = await sendOut(position.asset_In.id, position.amount_in, Principal.fromActor(main), null, quote.liq_provider_id, null);

        //special case of bad debt
        var total_debt = provided_Liquidity;
        var diff : Int = provided_Liquidity - total_debt;
        var pnl = 0;

        if (diff > 0) {
            total_debt := Nat64.toNat(position.debt) + fee;
            pnl := Int.abs(diff);
            ignore {
                //send pnl to trader
                await sendOut(position.asset_out.id, total_debt, Principal.fromActor(main), null, position.owner, null);
            };
        };

        let tx1 = await sendOut(position.asset_out.id, total_debt, Principal.fromActor(main), null, position.debt_pool, null);

        await main.removePosition(params.quote_asset.id, position, position.owner, params.position_id);
        await main.removeQuote(position.asset_In.id, params.quote_id);
    };

    public shared ({ caller }) func openPosition(params : OpenPositionParams, subaccount : ?Blob) : async () {
        //asserts all parameters are valid  check isOpenPositionValid to see full ilplemetation
        let res = await isOpenPositionValid(params);
        assert (res.valid == true);
        await _openPosition(caller, params, subaccount, res.margin_fee);
    };

    public shared ({ caller }) func closePosition(params : ClosePositionParams) : async () {
        assert (await isClosePositionValid(caller, params));
        await _closePosition(caller, params);
    };

};