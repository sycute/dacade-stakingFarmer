module stakingfarmer::farmer {
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object;
    use sui::table;
    use sui::tx_context;

    // Errors
    const EZero: u64 = 1;
    const ENotEnough: u64 = 2;

    public struct FARMER has drop {}
    public struct AdminCap has key { id: UID }

    public struct Record<phantom C> has key {
        id: UID,
        reward_rate: u64,           // Reward per second
        last_updated: u64,          // Last updated time (second)
        r: u64,                     // Reward per token
        user_r: table::Table<address, u64>,       // Address -> Reward per token
        user_staked: table::Table<address, u64>,  // Address -> Staked amount
        total_staked: Balance<C>,   // Total staked balance
        deci: u64,                  // Minimum stake limit
        rewards: table::Table<address, u64>,      // Address -> Rewards
    }

    /// Initialize the contract and transfer AdminCap to the sender
    public fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        transfer::transfer(AdminCap { id: object::new(ctx) }, sender);
    }

    /// Create a new record by admin
    public entry fun new_record<C>(
        _admin: &AdminCap,
        reward_rate: u64,
        deci: u64,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(deci > 0, EZero);

        transfer::share_object(Record<C> {
            id: object::new(ctx),
            reward_rate,
            last_updated: clock::timestamp_ms(clk) / 1000,
            r: 0,
            user_r: table::new(ctx),
            user_staked: table::new(ctx),
            total_staked: balance::zero<C>(),
            deci,
            rewards: table::new(ctx),
        });
    }

    /// User stakes coins and calculates rewards
    public entry fun stake<C>(
        record: &mut Record<C>,
        staked_coin: Coin<C>,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        let mut user_staked = coin::value(&staked_coin) / record.deci;
        assert!(user_staked > 0, ENotEnough);

        let user = tx_context::sender(ctx);
        let current = clock::timestamp_ms(clk) / 1000;

        let rpt = reward_per_token(record, current);
        let earned_amt = earned(record, rpt, user);

        // Update
        record.last_updated = current;
        record.r = rpt;
        table::add(&mut record.user_r, user, rpt);

        if (table::contains(&record.user_staked, user)) {
            let staked = table::remove(&mut record.user_staked, user);
            user_staked = user_staked + staked;
        }
        table::add(&mut record.user_staked, user, user_staked);
        balance::join(&mut record.total_staked, coin::into_balance(staked_coin));

        if (table::contains(&record.rewards, user)) {
            let e = table::remove(&mut record.rewards, user);
            table::add(&mut record.rewards, user, earned_amt + e);
        } else {
            table::add(&mut record.rewards, user, earned_amt);
        }
    }

    /// User withdraws coins and calculates rewards
    public entry fun withdraw<C>(
        record: &mut Record<C>,
        amount: u64,
        clk: &Clock,
        ctx: &mut TxContext
    ): Coin<C> {
        assert!(amount > 0, EZero);

        let user = tx_context::sender(ctx);
        let staked = table::remove(&mut record.user_staked, user);
        assert!(staked >= amount, ENotEnough);

        let current = clock::timestamp_ms(clk) / 1000;
        let rpt = reward_per_token(record, current);
        let earned_amt = earned(record, rpt, user);

        // Update
        record.last_updated = current;
        record.r = rpt;
        table::add(&mut record.user_r, user, rpt);
        table::add(&mut record.user_staked, user, staked - amount);

        let last_earned = table::remove(&mut record.rewards, user);
        table::add(&mut record.rewards, user, earned_amt + last_earned);

        coin::from_balance(balance::split(&mut record.total_staked, amount * record.deci), ctx)
    }

    /// User unstakes coins without withdrawing rewards
    public entry fun unstake<C>(
        record: &mut Record<C>,
        amount: u64,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(amount > 0, EZero);

        let user = tx_context::sender(ctx);
        let staked = table::remove(&mut record.user_staked, user);
        assert!(staked >= amount, ENotEnough);

        let current = clock::timestamp_ms(clk) / 1000;
        let rpt = reward_per_token(record, current);
        let earned_amt = earned(record, rpt, user);

        // Update
        record.last_updated = current;
        record.r = rpt;
        table::add(&mut record.user_r, user, rpt);
        table::add(&mut record.user_staked, user, staked - amount);

        let last_earned = table::remove(&mut record.rewards, user);
        table::add(&mut record.rewards, user, earned_amt + last_earned);
    }

    /// User claims rewards without unstaking
    public entry fun claim_rewards<C>(
        record: &mut Record<C>,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        let current = clock::timestamp_ms(clk) / 1000;
        let rpt = reward_per_token(record, current);
        let earned_amt = earned(record, rpt, user);

        // Update
        record.last_updated = current;
        record.r = rpt;
        table::add(&mut record.user_r, user, rpt);

        if (table::contains(&record.rewards, user)) {
            let e = table::remove(&mut record.rewards, user);
            table::add(&mut record.rewards, user, earned_amt + e);
        } else {
            table::add(&mut record.rewards, user, earned_amt);
        }
    }

    /// Calculate the earned rewards for a user
    public fun earned<C>(
        record: &mut Record<C>,
        reward_per_token: u64,
        sender: address
    ): u64 {
        let mut last_user_rpt = 0;
        let mut sender_staked = 0;
        if (table::contains(&record.user_r, sender)) {
            last_user_rpt = table::remove(&mut record.user_r, sender);
            sender_staked = *table::borrow(&record.user_staked, sender);
        }

        (reward_per_token - last_user_rpt) * sender_staked
    }

    /// Calculate reward per token
    public fun reward_per_token<C>(
        record: &Record<C>,
        current: u64
    ): u64 {
        let mut reward_per_token: u64 = 0;
        let total_staked = total_staked(record);
        if (total_staked != 0) {
            reward_per_token = (current - record.last_updated) * record.reward_rate / total_staked + record.r;
        }

        reward_per_token
    }

    /// Get the total staked amount
    public fun total_staked<C>(record: &Record<C>): u64 {
        balance::value(&record.total_staked)
    }

    /// Get the current staked balance of a user
    public fun staked_balance_of<C>(record: &Record<C>, user: address): u64 {
        if (table::contains(&record.user_staked, user)) {
            *table::borrow(&record.user_staked, user)
        } else {
            0
        }
    }

    #[test_only]
    public fun earned_of<C>(record: &Record<C>, owner: address): u64 {
        if (table::contains(&record.rewards, owner)) {
            *table::borrow(&record.rewards, owner)
        } else {
            0
        }
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx);
    }
}
