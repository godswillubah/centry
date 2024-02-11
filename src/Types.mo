import Text "mo:base/Text";
import Int "mo:base/Int";

module {

    type AssetClass = { #Cryptocurrency; #FiatCurrency };

    public type Asset = {
        id : Principal;
        symbol : Text;
        class_ : AssetClass;
    };

    public type TokenDetails = {
        is_allowed : Bool;
        max_debt : Nat64;
        min_collateral : Nat64;
        margin_fee : Nat64;
    };

    public type Range = {
        min : Nat64;
        max : Nat64;
    };
    public type Quote = {
        offer : Nat64;
        quote_asset : Asset;
        range : Range;
        time_limit : Int;
        liq_provider_id : Principal;

    };

    public type OpenPositionParams = {
        debt : Nat64;
        quote_id : Nat;
        pool_id : Nat;
        base_asset : Asset;
        collateral_amount : Nat64;
    };
    public type ClosePositionParams = {
        quote_asset : Asset;
        position_id : Nat;
        quote_id : Nat;
    };
    public type Position = {
        asset_In : Asset;
        asset_out : Asset;
        amount_in : Nat;
        debt_pool : Principal;
        debt : Nat64;
        marginFee : Nat64;
        timestamp : Int;
        owner : Principal;
    };
};