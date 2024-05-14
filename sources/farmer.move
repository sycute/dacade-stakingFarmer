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

    fun init(_wtn: FARMER, ctx: &mut TxContext) {
        transfer::transfer(AdminCap{id: object::new(ctx)}, ctx.sender());
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

    public fun pending_rewards<StakeCoin, RewardCoin>(
        farm: &Farm<StakeCoin, RewardCoin>,
        account: &Account<StakeCoin, RewardCoin>,
        c: &Clock,
    ): u64 {
        if (object::id(farm) != account.farm_id) return 0;

        let total_staked_value = balance::value(&farm.balance_stake_coin);
        let now = clock_timestamp_s(c);

        let cond = total_staked_value == 0 || farm.last_reward_timestamp >= now;

        let accrued_rewards_per_share = if (cond) {
          farm.accrued_rewards_per_share
        } else {
          calculate_accrued_rewards_per_share(
          farm.rewards_per_second,
          farm.accrued_rewards_per_share,
          total_staked_value,
          balance::value(&farm.balance_reward_coin),
          farm.stake_coin_decimal_factor,
          now - farm.last_reward_timestamp
          )
        };
        calculate_pending_rewards(account, farm.stake_coin_decimal_factor, accrued_rewards_per_share)
    }

    public fun stake<StakeCoin, RewardCoin>(
        farm: &mut Farm<StakeCoin, RewardCoin>,
        account: &mut Account<StakeCoin, RewardCoin>,
        stake_coin: Coin<StakeCoin>,
        c: &Clock,
        ctx: &mut TxContext
    ): Coin<RewardCoin> {
        assert!(object::id(farm) == account.farm_id, EInvalidAccount);

        update(farm, clock_timestamp_s(c));

        let stake_amount = coin::value(&stake_coin);

        let mut reward_coin = coin::zero<RewardCoin>(ctx);

        if (account.amount != 0) {
        let pending_reward = calculate_pending_rewards(
          account,
          farm.stake_coin_decimal_factor,
          farm.accrued_rewards_per_share
        );
        let pending_reward = min_u64(pending_reward, farm.balance_reward_coin.value());
        if (pending_reward != 0) {
          reward_coin.balance_mut().join(farm.balance_reward_coin.split(pending_reward));
        }
        };

        if (stake_amount != 0) {
          farm.balance_stake_coin.join(stake_coin.into_balance());
          account.amount = account.amount + stake_amount;
        } else {
          stake_coin.destroy_zero()
        };

        account.reward_debt = calculate_reward_debt(
          account.amount,
          farm.stake_coin_decimal_factor,
          farm.accrued_rewards_per_share
        );
        reward_coin
    }

    public fun unstake<StakeCoin, RewardCoin>(
        farm: &mut Farm<StakeCoin, RewardCoin>,
        account: &mut Account<StakeCoin, RewardCoin>,
        amount: u64,
        c: &Clock,
        ctx: &mut TxContext
    ): (Coin<StakeCoin>, Coin<RewardCoin>) {
        assert!(object::id(farm) == account.farm_id, EInvalidAccount);
        update(farm, clock_timestamp_s(c));

        assert!(account.amount >= amount, EInsufficientStakeAmount);

        let pending_reward = calculate_pending_rewards(
          account,
          farm.stake_coin_decimal_factor,
          farm.accrued_rewards_per_share
        );

        let mut stake_coin = coin::zero<StakeCoin>(ctx);
        let mut reward_coin = coin::zero<RewardCoin>(ctx);

        if (amount != 0) {
          account.amount = account.amount - amount;
          stake_coin.balance_mut().join(farm.balance_stake_coin.split(amount));
        };

        if (pending_reward != 0) {
          let pending_reward = min_u64(pending_reward, farm.balance_reward_coin.value());
          reward_coin.balance_mut().join(farm.balance_reward_coin.split(pending_reward));
        };

        account.reward_debt = calculate_reward_debt(
          account.amount,
          farm.stake_coin_decimal_factor,
          farm.accrued_rewards_per_share
        );

        (stake_coin, reward_coin)
    } 

    public fun add_rewards<StakeCoin, RewardCoin>(
        self: &mut Farm<StakeCoin, RewardCoin>, c: &Clock, reward: Coin<RewardCoin>
    ) {
        update(self, clock_timestamp_s(c));
        self.balance_reward_coin.join(reward.into_balance());
    }





  


    fun clock_timestamp_s(c: &Clock): u64 {
        clock::timestamp_ms(c) / 1000
    }

    fun calculate_pending_rewards<StakeCoin, RewardCoin>(acc: &Account<StakeCoin, RewardCoin>, stake_factor: u64, accrued_rewards_per_share: u256): u64 {
        ((((acc.amount as u256) * accrued_rewards_per_share / (stake_factor as u256)) - acc.reward_debt) as u64)
    }

    fun update<StakeCoin, RewardCoin>(farm: &mut Farm<StakeCoin, RewardCoin>, now: u64) {
        if (farm.last_reward_timestamp >= now || farm.start_timestamp> now) return;

        let total_staked_value = balance::value(&farm.balance_stake_coin);

        let prev_reward_time_stamp = farm.last_reward_timestamp;
        farm.last_reward_timestamp = now;

        if (total_staked_value == 0) return;

        let total_reward_value = balance::value(&farm.balance_reward_coin);

        farm.accrued_rewards_per_share = calculate_accrued_rewards_per_share(
          farm.rewards_per_second,
          farm.accrued_rewards_per_share,
          total_staked_value,
          total_reward_value,
          farm.stake_coin_decimal_factor,
          now - prev_reward_time_stamp
        );
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
    fun calculate_reward_debt(stake_amount: u64, stake_factor: u64, accrued_rewards_per_share: u256): u256 {
        let (stake_amount, stake_factor) = (
          (stake_amount as u256),
          (stake_factor as u256)
        );
        (stake_amount * accrued_rewards_per_share) / stake_factor
    }

    fun min(x: u256, y: u256): u256 {
        if (x < y) x else y
    }
    fun min_u64(x: u64, y: u64): u64 {
        if (x < y) x else y
    }

    
}
