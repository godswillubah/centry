/*
  The Main Canister Interface that stores

  Assets
  Positions
  Quotes
  Pools canisterID
  liquidity ProviderID

  Note:Some functions in here are restricted to the admins or clearingHouse canister like

  Adding new Debt Pools
  ading positions
  removing Positions


*/

import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Error "mo:base/Error";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";

import ICRC "Interface/ICRC";
import Pool "Pool";
import LiquidityProvider "LiquidityProvider";
import Types "Types";

shared ({ caller }) actor class Main(_clearingHouse : Principal, _priceFeed : Principal) = this {

    type LiquidityProvider = LiquidityProvider.LiquidityProvider;
    type Pool = Pool.Pool;
    type Token = ICRC.Token;
    type Asset = Types.Asset;

    type Quote = Types.Quote;

    type Position = Types.Position;

    // A position type  buffer to loop through positions
    type PositionBuffer = HashMap.HashMap<Principal, Buffer.Buffer<Position>>;

    let assetsList = Buffer.Buffer<Asset>(3);
    let pools = Buffer.Buffer<Principal>(3);
    let providers = Buffer.Buffer<Principal>(3);

    let user_POSITIONS = HashMap.HashMap<Principal, Buffer.Buffer<Position>>(1, Principal.equal, Principal.hash);

    let token_POSITIONS = HashMap.HashMap<Principal, Buffer.Buffer<Position>>(1, Principal.equal, Principal.hash);

    let token_QUOTES = HashMap.HashMap<Principal, Buffer.Buffer<Quote>>(1, Principal.equal, Principal.hash);

    stable let clearingHouse : Principal = _clearingHouse;
    stable let priceFeed : Principal = _priceFeed;
    stable let admin : Principal = caller;
    private func isAllowed(caller : Principal) : Bool {
        return caller == clearingHouse or caller == admin;
    };

    public query func getClearingHousePrincipal() : async Principal {
        return clearingHouse;
    };

    public query func getPriceFeed() : async Principal {
        return priceFeed;
    };

    public query func getAsset(id : Nat) : async Asset {
        return assetsList.get(id);
    };

    public query func getQuote(_token : Principal, id : Nat) : async Quote {
        let token_quotes = switch (token_QUOTES.get(_token)) {
            case (?res) { return res.get(id) };
            case (_) { throw Error.reject("") };
        };
    };

    public query func getPool(id : Nat) : async Principal {
        return pools.get(id);
    };

    //gets a position by looping through all the values in a Position type Buffer
    private func _getPositionID(_token : Principal, _position : Position, positionBuffer : PositionBuffer) : {
        #Ok : Nat;
        #Err : Text;
    } {
        let total_positions = switch (positionBuffer.get(_token)) {
            case (?res)(res);
            case (_) { return #Err("Token Positions not found") };
        };
        var counter = 0;
        label looping for (position in total_positions.vals()) {
            if (position == _position) {
                break looping;
            };
            counter += 1;
        };
        return #Ok(counter)

    };

    /*
    Stores a position for a token
       each position is associated with both a user and a token which is the base_asset of the trade

  */
    private func _storePosition(_token : Principal, _position : Position, _user : Principal) : async () {
        let total_pos : Buffer.Buffer<Position> = switch (token_POSITIONS.get(_token)) {
            case (?res) { res };
            case (_) { Buffer.Buffer<Position>(1) };
        };

        let user_positions : Buffer.Buffer<Position> = switch (user_POSITIONS.get(_user)) {
            case (?res) { res };
            case (_) { Buffer.Buffer<Position>(1) };
        };
        total_pos.add(_position);
        user_positions.add(_position);
        token_POSITIONS.put(_token, total_pos);
        user_POSITIONS.put(_user, user_positions);
    };

    /*
      Removes a position from the buffer list associated with the base_asset and the user positions buffer


      function can only be called by clearingHouse or allowed principals


    */
    private func _removePosition(_token : Principal, _position : Position, _user : Principal, _positonID : Nat) : async () {

        let total_positions = switch (token_POSITIONS.get(_token)) {
            case (?res) { res };
            case (_) { throw Error.reject("Token Positions not found") };
        };

        let user_positions = switch (user_POSITIONS.get(_user)) {
            case (?res) { res };
            case (_) { throw Error.reject("User position not found") };
        };

        let user_position_id = switch (_getPositionID(_token, _position, user_POSITIONS)) {
            case (#Ok(res)) { res };
            case (#Err(err)) {
                throw Error.reject("No user position with such id");
            };
        };
        ignore {
            let removedPosition = total_positions.remove(_positonID);
            user_positions.remove(user_position_id);
        };
        token_POSITIONS.put(_token, total_positions);
        user_POSITIONS.put(_user, user_positions);

    };

    public query func getPositionID(_token : Principal, _position : Position) : async Nat {
        let position_id = switch (_getPositionID(_token, _position, token_POSITIONS)) {
            case (#Ok(res)) { res };
            case (#Err(err)) { throw Error.reject(err) };
        };
    };

    private func _getPositionByID(_token : Principal, _positionID : Nat) : {
        #Ok : Position;
        #Err : Text;
    } {
        let token_positions = switch (token_POSITIONS.get(_token)) {
            case (?res) { res };
            case (_) { return #Err("Position not found") };
        };
        return #Ok(token_positions.get(_positionID));
    };

    public func getPositionByID(_token : Principal, _positionID : Nat) : async Position {
        switch (_getPositionByID(_token, _positionID)) {
            case (#Ok(res)) { return res };
            case (#Err(err))(throw Error.reject(err));
        };

    };

    // createPool function can only be called by admin to restrict bad actord from wasting cycles and ensure only
    //interested personnels participate
    public shared ({ caller }) func createPool(poolPrincipal : Principal) : async Nat {
        assert (isAllowed(caller));
        pools.add(poolPrincipal);
        return pools.size() + 1;
    };

    /*
      sets a Quote for a particular which in this case is the base_asset


        public type Quote = {
        offer : Nat64;   ~ the premium in percentage that you would have the quote taker i.e trader has to pay
        quote_asset : Asset;  ~ The asset the provider is willing to give for the base asset
        range : Range;        ~A range of the amount of quote_asset allowed for this quote
        time_limit : Int;      ~ A time limit to ensure protect liquidity providers from future use of this quote
        liq_provider_id : Principal;  ~ the canister id or principal the created that quote

    };

    */

    public shared ({ caller }) func setQuote(_token : Principal, _providerID : Nat, quote : Quote) : async Nat {
        let providerPrincipal : Principal = quote.liq_provider_id;
        let liq_Provider : LiquidityProvider = actor (Principal.toText(providerPrincipal));

        // Asserts caller is either liquidity provider pool admin
        assert (caller == (await liq_Provider.getAdmin()));
        let token_quotes = switch (token_QUOTES.get(_token)) {
            case (?res) { res };
            case (_) { throw Error.reject("Token Not Foumd") }; //prevents creation of quotes fro unknown tokens
        };
        token_quotes.add(quote);
        return token_quotes.size() - 1;

    };

    /* Removes a quote given its id

   `` can only be called by clearingHouse canister of the principal identity that set the Quote

   */
    public shared ({ caller }) func removeQuote(_token : Principal, _quoteID : Nat) : async () {
        let token_quotes = switch (token_QUOTES.get(_token)) {
            case (?res) { res };
            case (_) { throw Error.reject("Token Quotes not found") };
        };

        //gets th quote
        let quote : Quote = token_quotes.get(_quoteID);

        let providerPrincipal : Principal = quote.liq_provider_id;
        let provider : LiquidityProvider = actor (Principal.toText(providerPrincipal));

        /* checks that the principal assigned as admin of that liquidity provider canister is the one calling the function
          This can also be called by the admin principal id of this canister for quotes that

          `Have become too old
          `Tokens that have been removed

           */
        assert (caller == (await provider.getAdmin()) or isAllowed(caller));
        ignore (token_quotes.remove(_quoteID));
    };

    //stores a position
    public shared ({ caller }) func storePosition(_token : Principal, _position : Position, _user : Principal) : async () {
        assert (isAllowed(caller));
        return await _storePosition(_token, _position, _user);
    };

    //removes a position from storage
    public shared ({ caller }) func removePosition(_token : Principal, _position : Position, _user : Principal, _positionID : Nat) : async () {
        assert (isAllowed(caller));
        return await _removePosition(_token, _position, _user, _positionID);
    };

    //Approves the clearingHouse to spend the entire balance of this actor ;
    //function can onnly be called by admin
    //
    public shared ({ caller }) func approve(tokenPrincipal : Principal) : async () {
        assert (isAllowed(caller));
        let token : Token = actor (Principal.toText(tokenPrincipal));
        let balance = await token.icrc1_balance_of({
            owner = Principal.fromActor(this);
            subaccount = null;
        });
        let fee = await token.icrc1_fee();
        ignore {
            await token.icrc2_approve({
                from_subaccount = null;
                spender = { owner = clearingHouse; subaccount = null };
                amount = balance;
                expires_at = null;
                expected_allowance = ?balance;
                memo = null;
                fee = ?fee;
                created_at_time = null;
            });
        };
    };
};
