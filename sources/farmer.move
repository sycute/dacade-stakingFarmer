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

    public struct Farm<phantom StakeCoin, phantom RewardCoin> has key, store {
        id: UID,
        // Amount of {RewardCoin} to give to stakers per second.
        rewards_per_second: u64,
        // The timestamp in seconds that this farm will start distributing rewards.
        start_timestamp: u64,
        // Last timestamp that the farm was updated.
        last_reward_timestamp: u64,
        // Total amount of rewards per share distributed by this farm.
        accrued_rewards_per_share: u256,
        // {StakeCoin} deposited in this farm.
        balance_stake_coin: Balance<StakeCoin>,
        // {RewardCoin} deposited in this farm.
        balance_reward_coin: Balance<RewardCoin>,
        // The decimal scalar of the {StakeCoin}.
        stake_coin_decimal_factor: u64,
        // The `sui::object::ID` of the {OwnerCap} that "owns" this farm.
        owned_by: ID
    }

    public struct FarmCap has key, store {
        id: UID,
        farm: ID
    }

    public struct Account<phantom StakeCoin, phantom RewardCoin> has key, store {
        id: UID,
        // The `sui::object::ID` of the farm to which this account belongs to.
        farm_id: ID,
        // The amount of {StakeCoin} the user has in the {Farm}.
        amount: u64,
        // Amount of rewards the {Farm} has already paid the user.
        reward_debt: u256
    }



    fun init(_wtn: FARMER, ctx: &mut TxContext) {
        transfer::transfer(AdminCap{id: object::new(ctx)}, ctx.sender());
    }

    
}
