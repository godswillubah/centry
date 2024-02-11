import Principal "mo:base/Principal";
module {
    public type TxReceipt = {
        #Ok : Nat;
        #Err : {
            #InsufficientAllowance;
            #InsufficientBalance;
            #ErrorOperationStyle;
            #Unauthorized;
            #LedgerTrap;
            #ErrorTo;
            #Other;
            #BlockUsed;
            #AmountTooSmall;
        };
    };

    public type DIP20 = actor {
        transfer : (Principal, Nat) -> async TxReceipt;
        transferFrom : (Principal, Principal, Nat) -> async TxReceipt;
        getTokenFee : query () -> async Nat;
    };
};