module stakingfarmer::farmer {
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::table;

    // Errors
    const E_ZERO: u64 = 1;
    const E_NOT_ENOUGH: u64 = 2;

    public struct FARMER has drop {}
    public struct AdminCap has key { id: UID }

    public struct Record has key {
        id: UID,
        /// Reward per second
        reward_rate: u64,
        /// Last updated time (second)
        last_updated: u64,
        /// Reward per token
        r: u64,
        /// Address -> Reward per token
        user_r: table::Table<address, u64>,
        /// Address -> Staked amount
        user_staked: table::Table<address, u64>,
        /// Total staked amount
        total_staked: u64,
        /// Minimum staked amount
        deci: u64,
        /// Address -> Reward
        rewards: table::Table<address, u64>,
    }

    fun init(_wtn: FARMER, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        transfer::transfer(AdminCap { id: object::new(ctx) }, sender);
    }

    /// Create a record by admin
    public entry fun new_record(_admin: &AdminCap, reward_rate: u64, deci: u64, clk: &Clock, ctx: &mut TxContext) {
        assert!(deci > 0, E_ZERO);
        transfer::share_object(Record {
            id: object::new(ctx),
            reward_rate,
            last_updated: clock::timestamp_ms(clk) / 1000,
            r: 0,
            user_r: table::new(ctx),
            user_staked: table::new(ctx),
            total_staked: 0,
            deci,
            rewards: table::new(ctx),
        });
    }

    /// User stakes coins and calculates rewards
    public entry fun stake(record: &mut Record, staked_coin: Coin, clk: &Clock, ctx: &mut TxContext) {
        let current = clock::timestamp_ms(clk) / 1000;
        let rpt = reward_per_token(record, current);
        let user_staked = coin::value(&staked_coin) / record.deci;
        assert!(user_staked > 0, E_NOT_ENOUGH);
        let earned_amt = earned(record, rpt, tx_context::sender(ctx));
        // Update
        record.last_updated = current;
        record.r = rpt;
        table::add(&mut record.user_r, tx_context::sender(ctx), rpt);
        if let Some(staked) = table::remove(&mut record.user_staked, tx_context::sender(ctx)) {
            user_staked += staked;
        }
        table::add(&mut record.user_staked, tx_context::sender(ctx), user_staked);
        balance::join(&mut record.total_staked, coin::into_balance(staked_coin));
        if let Some(e) = table::remove(&mut record.rewards, tx_context::sender(ctx)) {
            table::add(&mut record.rewards, tx_context::sender(ctx), earned_amt + e);
        } else {
            table::add(&mut record.rewards, tx_context::sender(ctx), earned_amt);
        }
    }

    /// User withdraws coins and calculates rewards
    public fun withdraw(record: &mut Record, amount: u64, clk: &Clock, ctx: &mut TxContext) -> Coin {
        assert!(amount > 0, E_ZERO);
        let user = tx_context::sender(ctx);
        let staked = table::remove(&mut record.user_staked, user).unwrap_or(0);
        assert!(staked >= amount, E_NOT_ENOUGH);
        let current = clock::timestamp_ms(clk) / 1000;
        let rpt = reward_per_token(record, current);
        let earned_amt = earned(record, rpt, user);
        // Update
        record.last_updated = current;
        record.r = rpt;
        table::add(&mut record.user_r, user, rpt);
        table::add(&mut record.user_staked, user, staked - amount);
        let last_earned = table::remove(&mut record.rewards, user).unwrap_or(0);
        table::add(&mut record.rewards, user, earned_amt + last_earned);
        coin::from_balance(balance::split(&mut record.total_staked, amount * record.deci), ctx)
    }

    public fun earned(record: &Record, reward_per_token: u64, sender: address) -> u64 {
        let last_user_rpt = *table::borrow(&record.user_r, sender);
        let sender_staked = *table::borrow(&record.user_staked, sender);
        (reward_per_token - last_user_rpt) * sender_staked
    }

    public fun reward_per_token(record: &Record, current: u64) -> u64 {
        let total_staked = record.total_staked;
        if total_staked == 0 {
            return record.r;
        }
        (current - record.last_updated) * record.reward_rate / total_staked + record.r
    }

    fun total_staked(record: &Record) -> u64 {
        record.total_staked
    }

    #[test_only]
    public fun earned_of(record: &Record, owner: address) -> u64 {
        *table::borrow(&record.rewards, owner)
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(FARMER {}, ctx);
    }
}
