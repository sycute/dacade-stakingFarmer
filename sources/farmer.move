module stakingfarmer::farmer {
    use sui::balance::{Self,Balance};
    use sui::clock::{Self, Clock, timestamp_ms};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::coin::{CoinMetadata};
    use sui::math;

    // Errors
    const EInsufficientStakeAmount: u64 = 0;
    const EAccountHasValue: u64 = 1;
    const EInvalidStartTime: u64 = 2;
    const EInvalidAccount: u64 = 3;

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

    public fun new_farm<StakeCoin, RewardCoin>(
        stake_coin_metadata: &CoinMetadata<StakeCoin>,
        c: &Clock,
        rewards_per_second: u64,
        start_timestamp: u64,
        ctx: &mut TxContext
    ): (Farm<StakeCoin, RewardCoin>, FarmCap) {
        assert!(start_timestamp > clock_timestamp_s(c), EInvalidStartTime);
        let id_ = object::new(ctx);
        let inner_ = object::uid_to_inner(&id_);

        let cap_id = object::new(ctx);
        let cap_inner = object::uid_to_inner(&cap_id);

        let cap = FarmCap {
            id: cap_id,
            farm: inner_
        };

        let farm = Farm {
          id: id_,
          start_timestamp,
          last_reward_timestamp: start_timestamp,
          rewards_per_second,
          accrued_rewards_per_share: 0,
          stake_coin_decimal_factor: math::pow(10, coin::get_decimals(stake_coin_metadata)),
          owned_by: cap_inner,
          balance_stake_coin: balance::zero(),
          balance_reward_coin: balance::zero(),
        };

        (farm, cap)
    }   
    public fun new_account<StakeCoin, RewardCoin>(
        self: &Farm<StakeCoin, RewardCoin>,
        ctx: &mut TxContext
    ): Account<StakeCoin, RewardCoin> {
        Account {
        id: object::new(ctx),
        farm_id: object::id(self),
        amount: 0,
        reward_debt: 0
        }
    }   





    fun init(_wtn: FARMER, ctx: &mut TxContext) {
        transfer::transfer(AdminCap{id: object::new(ctx)}, ctx.sender());
    }


    fun clock_timestamp_s(c: &Clock): u64 {
        clock::timestamp_ms(c) / 1000
    }

    fun calculate_pending_rewards<StakeCoin, RewardCoin>(acc: &Account<StakeCoin, RewardCoin>, stake_factor: u64, accrued_rewards_per_share: u256): u64 {
        ((((acc.amount as u256) * accrued_rewards_per_share / (stake_factor as u256)) - acc.reward_debt) as u64)
    }

    fun calculate_accrued_rewards_per_share(
        rewards_per_second: u64,
        last_accrued_rewards_per_share: u256,
        total_staked_token: u64,
        total_reward_value: u64,
        stake_factor: u64,
        timestamp_delta: u64
    ): u256 {

        let (total_staked_token, total_reward_value, rewards_per_second, stake_factor, timestamp_delta) =
         (
          (total_staked_token as u256),
          (total_reward_value as u256),
          (rewards_per_second as u256),
          (stake_factor as u256),
          (timestamp_delta as u256)
         );

        let reward = min(total_reward_value, rewards_per_second * timestamp_delta);

        last_accrued_rewards_per_share + ((reward * stake_factor) / total_staked_token)
    }

    fun min(x: u256, y: u256): u256 {
        if (x < y) x else y
    }

    
}
