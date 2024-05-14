module stakingfarmer::farmer {
    use sui::balance::{Self,Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};

    // Errors
    const EZero: u64 = 1;
    const ENotEnough: u64 = 2;

    public struct FARMER has drop {}
    public struct AdminCap has key {id: UID}



    fun init(_wtn: FARMER, ctx: &mut TxContext) {
        transfer::transfer(AdminCap{id: object::new(ctx)}, ctx.sender());
    }

    
}
