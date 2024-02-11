/*
This is a simple Liquidity provider Canister that can be controlled by the admin which can be an individual or a DAO,
it contains simple functions like
 withdrawing out tokens
  approving the clearingHouse to spend your tokens,

NOTE:Most of these functions can only be called the admin or the clearingHouse canister



*/

import DIP20 "Interface/DIP20";
import ICRC "Interface/ICRC";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Error "mo:base/Error";

actor class Pool(admin : Principal, clearingHouse : Principal) {
    type Token = ICRC.Token;

    type TokenDetails = {
        is_allowed : Bool;
        max_debt : Nat64;
        min_collateral : Nat64;
        margin_fee : Nat64;
    };

    stable let init = false;

    //checks if caller is allowed to call that function
    func isCallerAllowed(caller : Principal) : Bool {
        return (caller == admin or caller == clearingHouse);
    };

    //maps each tokenPrincipal to the details
    let tokendetails = HashMap.HashMap<Principal, TokenDetails>(1, Principal.equal, Principal.hash);
    let isliquidator = HashMap.HashMap<Principal, Bool>(1, Principal.equal, Principal.hash);

    /*
    Retreives the tokendetials of a particular token relative to this pool r
    Returns a variable of TokenDetail type  with is_allowed attribute set to false

     */
    public query func getTokenDetails(_token : Principal) : async TokenDetails {
        let token_details : TokenDetails = switch (tokendetails.get(_token)) {
            case (?res) { res };
            case (_) {
                {
                    is_allowed = false;
                    max_debt = 0;
                    min_collateral = 0;
                    margin_fee = 0;
                };
            };
        };
    };

    //sets an a principal as an operator or remove an already existing operator
    public shared ({ caller }) func setOperator(operator : Principal, status : Bool) : async () {
        isliquidator.put(operator, status);
    };

    // checks if a particular adddress is a has the permission to take back loan from traders by liquidating their position
    public shared ({ caller }) func isLiquidator(operator : Principal) : async Bool {
        let status = switch (isliquidator.get(operator)) {
            case (?res) { res };
            case (_) { false };
        };
    };
    public shared ({ caller }) func setToken(tokenPrincipal : Principal, status : TokenDetails) : async () {
        tokendetails.put(tokenPrincipal, status);
    };

    public shared ({ caller }) func sendOutICRC(tokenPrincipal : Principal, to : Principal, amount : Nat) : async Nat {
        assert (isCallerAllowed(caller));
        let token : Token = actor (Principal.toText(tokenPrincipal));
        let fee = await token.icrc1_fee();
        let sending_amount : Nat = amount - fee;
        let tx = await token.icrc1_transfer({
            from_subaccount = null;
            to = {
                owner = to;
                subaccount = null;
            };
            amount = sending_amount;
            fee = ?fee;
            memo = null;
            created_at_time = null;

        });

        let isValid = switch (tx) {
            case (#Ok(num)) { true };
            case (#Err(err)) { false };
        };
        assert (isValid);
        return sending_amount;

    };

    //used to set approval to the clearingHouse canister

    public shared ({ caller }) func approve(tokenPrincipal : Principal, amount : Nat) : async () {
        assert (isCallerAllowed(caller));
        let token : Token = actor (Principal.toText(tokenPrincipal));
        let fee = await token.icrc1_fee();
        ignore {
            await token.icrc2_approve({
                from_subaccount = null;
                spender = { owner = clearingHouse; subaccount = null };
                amount = amount;
                expires_at = null;
                expected_allowance = ?amount;
                memo = null;
                fee = ?fee;
                created_at_time = null;
            });
        };
    };

};