#[allow(lint(public_entry))]
module prediction_market::market {
    use prediction_market::config;
    use prediction_market::errors;
    use prediction_market::events;
    use prediction_market::registry;
    use prediction_market::resolution_state;
    use std::string::String;
    use sui::balance;
    use sui::balance::Balance;
    use sui::clock;
    use sui::clock::Clock;
    use sui::coin;
    use sui::coin::Coin;
    use sui::table;
    use sui::table::Table;
    use sui::tx_context::sender;

    /// Owned position object so users keep custody of their YES/NO exposure.
    public struct Position<phantom T> has key, store {
        id: UID,
        market_id: ID,
        owner: address,
        side_yes: bool,
        shares: u64,
    }

    /// LP position tracks a share of pooled liquidity. Owned by LP.
    public struct LPPosition<phantom T> has key, store {
        id: UID,
        market_id: ID,
        shares: u64,
    }

    /// Shared market object: shared so all users can trade/discover on-chain.
    /// Generic over coin type T.
    public struct Market<phantom T> has key, store {
        id: UID,
        registry_id: ID,
        question: String,
        end_time_ms: u64,
        fee_bps: u64,
        resolved: bool,
        outcome_yes: bool,
        yes_vault: Balance<T>,
        no_vault: Balance<T>,
        total_yes_shares: u64,
        total_no_shares: u64,
        total_lp_shares: u64,
        orders: Table<ID, bool>,
        has_pending: bool,
        pending: resolution_state::PendingResolution<T>,
    }

    /// Create a market with initial balanced liquidity provided by the admin.
    /// Returns shared Market<T> (caller should share) and an LP position to the admin.
    public fun create_market<T>(
        admin: &config::AdminCap,
        cfg: &config::ProtocolConfig<T>,
        registry_obj: &mut registry::MarketRegistry,
        clock_obj: &Clock,
        question: String,
        end_time_ms: u64,
        fee_bps: u64,
        mut liquidity: Coin<T>,
        ctx: &mut sui::tx_context::TxContext,
    ): (Market<T>, LPPosition<T>) {
        config::assert_admin(admin, sender(ctx));
        assert!(!config::is_paused(cfg), errors::epaused());
        assert!(fee_bps <= 10_000, errors::efee());
        assert!(clock::timestamp_ms(clock_obj) < end_time_ms, errors::eended());

        let half = coin::value(&liquidity) / 2;
        let half_coin = coin::split(&mut liquidity, half, ctx);
        let yes_bal = coin::into_balance(half_coin);
        let no_bal = coin::into_balance(liquidity);

        let market = Market<T> {
            id: sui::object::new(ctx),
            registry_id: sui::object::id(registry_obj),
            question,
            end_time_ms,
            fee_bps,
            resolved: false,
            outcome_yes: false,
            yes_vault: yes_bal,
            no_vault: no_bal,
            total_yes_shares: half,
            total_no_shares: half,
            total_lp_shares: half,
            orders: table::new(ctx),
            has_pending: false,
            pending: resolution_state::empty<T>(),
        };
        let lp = LPPosition<T> { id: sui::object::new(ctx), market_id: sui::object::id(&market), shares: half };
        registry::register(registry_obj, sui::object::id(&market));
        events::emit_market_created(sui::object::id(&market), sui::object::id(registry_obj), market.question, end_time_ms);
        (market, lp)
    }

    public fun ensure_open<T>(market: &Market<T>, cfg: &config::ProtocolConfig<T>, clock_obj: &Clock) {
        assert!(!config::is_paused(cfg), errors::epaused());
        assert!(!market.resolved, errors::eresolved());
        let now = clock::timestamp_ms(clock_obj);
        assert!(now < market.end_time_ms, errors::eended());
    }

    fun apply_fee<T>(cfg: &config::ProtocolConfig<T>, amount: u64): (u64, u64) {
        let fee = amount * config::fee_bps(cfg) / 10_000;
        (amount - fee, fee)
    }

    public fun buy_yes<T>(
        cfg: &mut config::ProtocolConfig<T>,
        market: &mut Market<T>,
        clock_obj: &Clock,
        beneficiary: address,
        mut payment: Coin<T>,
        min_shares: u64,
        ctx: &mut sui::tx_context::TxContext,
    ): Position<T> {
        ensure_open(market, cfg, clock_obj);
        let amount_in = coin::value(&payment);
        let (trade_amount, fee_amount) = apply_fee(cfg, amount_in);
        let fee_coin = coin::split(&mut payment, fee_amount, ctx);
        let trade_coin = payment;
        config::deposit_fee(cfg, coin::into_balance(fee_coin));

        let yes_before = balance::value(&market.yes_vault);
        let no_before = balance::value(&market.no_vault);
        let shares_out = (trade_amount * no_before) / (yes_before + trade_amount);
        assert!(shares_out >= min_shares, errors::eslippage());

        balance::join(&mut market.yes_vault, coin::into_balance(trade_coin));
        market.total_yes_shares = market.total_yes_shares + shares_out;

        let pos = Position<T> {
            id: sui::object::new(ctx),
            market_id: sui::object::id(market),
            owner: beneficiary,
            side_yes: true,
            shares: shares_out,
        };
        events::emit_trade(sui::object::id(market), beneficiary, true, amount_in, shares_out, fee_amount);
        pos
    }

    public fun buy_no<T>(
        cfg: &mut config::ProtocolConfig<T>,
        market: &mut Market<T>,
        clock_obj: &Clock,
        beneficiary: address,
        mut payment: Coin<T>,
        min_shares: u64,
        ctx: &mut sui::tx_context::TxContext,
    ): Position<T> {
        ensure_open(market, cfg, clock_obj);
        let amount_in = coin::value(&payment);
        let (trade_amount, fee_amount) = apply_fee(cfg, amount_in);
        let fee_coin = coin::split(&mut payment, fee_amount, ctx);
        let trade_coin = payment;
        config::deposit_fee(cfg, coin::into_balance(fee_coin));

        let yes_before = balance::value(&market.yes_vault);
        let no_before = balance::value(&market.no_vault);
        let shares_out = (trade_amount * yes_before) / (no_before + trade_amount);
        assert!(shares_out >= min_shares, errors::eslippage());

        balance::join(&mut market.no_vault, coin::into_balance(trade_coin));
        market.total_no_shares = market.total_no_shares + shares_out;

        let pos = Position<T> {
            id: sui::object::new(ctx),
            market_id: sui::object::id(market),
            owner: beneficiary,
            side_yes: false,
            shares: shares_out,
        };
        events::emit_trade(sui::object::id(market), beneficiary, false, amount_in, shares_out, fee_amount);
        pos
    }

    public fun sell_yes<T>(
        cfg: &mut config::ProtocolConfig<T>,
        market: &mut Market<T>,
        clock_obj: &Clock,
        pos: Position<T>,
        min_amount_out: u64,
        ctx: &mut sui::tx_context::TxContext,
    ): Coin<T> {
        ensure_open(market, cfg, clock_obj);
        let Position { id, market_id: _, owner: _, side_yes, shares } = pos;
        assert!(side_yes, errors::eorder());
        let total_shares = market.total_yes_shares;
        assert!(shares > 0 && shares <= total_shares, errors::einsufficient());
        let vault_val = balance::value(&market.yes_vault);
        let amount_out_raw = shares * vault_val / total_shares;
        assert!(amount_out_raw >= min_amount_out, errors::eslippage());
        let (amount_out, fee_amount) = apply_fee(cfg, amount_out_raw);
        let total_out_bal = balance::split(&mut market.yes_vault, amount_out_raw);
        let mut total_out_coin = coin::from_balance(total_out_bal, ctx);
        if (fee_amount > 0) {
            let fee_coin = coin::split(&mut total_out_coin, fee_amount, ctx);
            config::deposit_fee(cfg, coin::into_balance(fee_coin));
        }
        market.total_yes_shares = market.total_yes_shares - shares;
        sui::object::delete(id);
        events::emit_sell(sui::object::id(market), sender(ctx), true, shares, amount_out, fee_amount);
        total_out_coin
    }

    public fun sell_no<T>(
        cfg: &mut config::ProtocolConfig<T>,
        market: &mut Market<T>,
        clock_obj: &Clock,
        pos: Position<T>,
        min_amount_out: u64,
        ctx: &mut sui::tx_context::TxContext,
    ): Coin<T> {
        ensure_open(market, cfg, clock_obj);
        let Position { id, market_id: _, owner: _, side_yes, shares } = pos;
        assert!(!side_yes, errors::eorder());
        let total_shares = market.total_no_shares;
        assert!(shares > 0 && shares <= total_shares, errors::einsufficient());
        let vault_val = balance::value(&market.no_vault);
        let amount_out_raw = shares * vault_val / total_shares;
        assert!(amount_out_raw >= min_amount_out, errors::eslippage());
        let (amount_out, fee_amount) = apply_fee(cfg, amount_out_raw);
        let total_out_bal = balance::split(&mut market.no_vault, amount_out_raw);
        let mut total_out_coin = coin::from_balance(total_out_bal, ctx);
        if (fee_amount > 0) {
            let fee_coin = coin::split(&mut total_out_coin, fee_amount, ctx);
            config::deposit_fee(cfg, coin::into_balance(fee_coin));
        }
        market.total_no_shares = market.total_no_shares - shares;
        sui::object::delete(id);
        events::emit_sell(sui::object::id(market), sender(ctx), false, shares, amount_out, fee_amount);
        total_out_coin
    }

    public fun add_liquidity<T>(
        cfg: &config::ProtocolConfig<T>,
        market: &mut Market<T>,
        clock_obj: &Clock,
        mut liquidity: Coin<T>,
        min_lp_shares: u64,
        ctx: &mut sui::tx_context::TxContext,
    ): LPPosition<T> {
        ensure_open(market, cfg, clock_obj);
        let deposit_amount = coin::value(&liquidity);
        let half = deposit_amount / 2;
        let half_coin = coin::split(&mut liquidity, half, ctx);
        balance::join(&mut market.yes_vault, coin::into_balance(half_coin));
        balance::join(&mut market.no_vault, coin::into_balance(liquidity));

        let lp_shares = half;
        assert!(lp_shares >= min_lp_shares, errors::eslippage());
        market.total_yes_shares = market.total_yes_shares + half;
        market.total_no_shares = market.total_no_shares + half;
        market.total_lp_shares = market.total_lp_shares + lp_shares;

        events::emit_liquidity(sui::object::id(market), sender(ctx), true, half, half, lp_shares);
        LPPosition<T> { id: sui::object::new(ctx), market_id: sui::object::id(market), shares: lp_shares }
    }

    public fun remove_liquidity<T>(
        market: &mut Market<T>,
        lp: LPPosition<T>,
        ctx: &mut sui::tx_context::TxContext,
    ): Coin<T> {
        let LPPosition { id, market_id: _, shares } = lp;
        let total_lp = market.total_lp_shares;
        assert!(shares <= total_lp, errors::einsufficient());
        let yes_before = balance::value(&market.yes_vault);
        let no_before = balance::value(&market.no_vault);
        let yes_out_amount = shares * yes_before / total_lp;
        let no_out_amount = shares * no_before / total_lp;
        let yes_out = balance::split(&mut market.yes_vault, yes_out_amount);
        let no_out = balance::split(&mut market.no_vault, no_out_amount);

        let mut bank = yes_out;
        balance::join(&mut bank, no_out);
        market.total_lp_shares = market.total_lp_shares - shares;
        sui::object::delete(id);
        events::emit_liquidity(sui::object::id(market), sender(ctx), false, balance::value(&bank), 0, shares);
        coin::from_balance(bank, ctx)
    }

    /// Redeem after resolution. Losers get nothing; winners get pro-rata vault.
    public fun redeem<T>(
        market: &mut Market<T>,
        pos: Position<T>,
        ctx: &mut sui::tx_context::TxContext,
    ): Coin<T> {
        assert!(market.resolved, errors::eresolved());
        let Position { id, market_id: _, owner: _, side_yes, shares } = pos;
        let winning = (market.outcome_yes && side_yes) || (!market.outcome_yes && !side_yes);
        assert!(shares > 0, errors::enothing());
        if (winning) {
            if (side_yes) {
                let vault_val = balance::value(&market.yes_vault);
                let payout = balance::split(&mut market.yes_vault, shares * vault_val / market.total_yes_shares);
                market.total_yes_shares = market.total_yes_shares - shares;
                sui::object::delete(id);
                coin::from_balance(payout, ctx)
            } else {
                let vault_val = balance::value(&market.no_vault);
                let payout = balance::split(&mut market.no_vault, shares * vault_val / market.total_no_shares);
                market.total_no_shares = market.total_no_shares - shares;
                sui::object::delete(id);
                coin::from_balance(payout, ctx)
            }
        } else {
            sui::object::delete(id);
            coin::from_balance(balance::zero<T>(), ctx)
        }
    }

    public fun transfer_position<T>(mut pos: Position<T>, new_owner: address): Position<T> {
        pos.owner = new_owner;
        pos
    }

    public fun is_resolved<T>(market: &Market<T>): bool { market.resolved }

    public fun has_pending<T>(market: &Market<T>): bool { market.has_pending }

    public fun pending_mut<T>(market: &mut Market<T>): &mut resolution_state::PendingResolution<T> { &mut market.pending }

    public fun consume_pending<T>(market: &mut Market<T>): (bool, sui::balance::Balance<T>) {
        market.has_pending = false;
        resolution_state::consume(&mut market.pending)
    }

    public fun set_pending<T>(market: &mut Market<T>, proposer: address, outcome_yes: bool, bond: sui::balance::Balance<T>) {
        market.has_pending = true;
        resolution_state::start(&mut market.pending, proposer, outcome_yes, bond);
    }

    public fun mark_resolved<T>(market: &mut Market<T>, outcome_yes: bool) {
        market.resolved = true;
        market.outcome_yes = outcome_yes;
    }

    public fun end_time<T>(market: &Market<T>): u64 { market.end_time_ms }

    public fun market_id<T>(market: &Market<T>): ID { sui::object::id(market) }

    public fun orders_table_mut<T>(market: &mut Market<T>): &mut Table<ID, bool> { &mut market.orders }

    public fun has_order<T>(market: &Market<T>, order_id: ID): bool { table::contains(&market.orders, order_id) }

    public fun register_order<T>(market: &mut Market<T>, order_id: ID) { table::add(&mut market.orders, order_id, true) }

    public fun clear_order<T>(market: &mut Market<T>, order_id: ID) { table::remove(&mut market.orders, order_id); }

    public fun position_shares<T>(pos: &Position<T>): u64 { pos.shares }

    public fun position_side<T>(pos: &Position<T>): bool { pos.side_yes }

    public fun yes_price_bps<T>(market: &Market<T>): u64 {
        let total = balance::value(&market.yes_vault) + balance::value(&market.no_vault);
        if (total == 0) { 5000 } else { balance::value(&market.yes_vault) * 10_000 / total }
    }

    public fun no_price_bps<T>(market: &Market<T>): u64 { 10_000 - yes_price_bps(market) }

    /// Create a position without balancing vault math (used by limit orders).
    public fun mint_position<T>(market: &Market<T>, owner: address, side_yes: bool, shares: u64, ctx: &mut sui::tx_context::TxContext): Position<T> {
        Position<T> { id: sui::object::new(ctx), market_id: sui::object::id(market), owner, side_yes, shares }
    }

    /// Entry wrappers for transaction builders to automatically transfer outputs.
    #[allow(lint(share_owned))]
    public entry fun entry_create_market<T>(
        admin: &config::AdminCap,
        cfg: &config::ProtocolConfig<T>,
        registry_obj: &mut registry::MarketRegistry,
        clock_obj: &Clock,
        question: String,
        end_time_ms: u64,
        fee_bps: u64,
        liquidity: Coin<T>,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let sender_addr = sender(ctx);
        let (market_obj, lp) = create_market<T>(admin, cfg, registry_obj, clock_obj, question, end_time_ms, fee_bps, liquidity, ctx);
        sui::transfer::share_object(market_obj);
        sui::transfer::public_transfer(lp, sender_addr);
    }

    public entry fun entry_buy_yes<T>(
        cfg: &mut config::ProtocolConfig<T>,
        market: &mut Market<T>,
        clock_obj: &Clock,
        payment: Coin<T>,
        min_shares: u64,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let buyer = sender(ctx);
        let pos = buy_yes<T>(cfg, market, clock_obj, buyer, payment, min_shares, ctx);
        sui::transfer::public_transfer(pos, buyer);
    }

    public entry fun entry_buy_no<T>(
        cfg: &mut config::ProtocolConfig<T>,
        market: &mut Market<T>,
        clock_obj: &Clock,
        payment: Coin<T>,
        min_shares: u64,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let buyer = sender(ctx);
        let pos = buy_no<T>(cfg, market, clock_obj, buyer, payment, min_shares, ctx);
        sui::transfer::public_transfer(pos, buyer);
    }

    public entry fun entry_sell_yes<T>(
        cfg: &mut config::ProtocolConfig<T>,
        market: &mut Market<T>,
        clock_obj: &Clock,
        pos: Position<T>,
        min_amount_out: u64,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let coins = sell_yes<T>(cfg, market, clock_obj, pos, min_amount_out, ctx);
        sui::transfer::public_transfer(coins, sender(ctx));
    }

    public entry fun entry_sell_no<T>(
        cfg: &mut config::ProtocolConfig<T>,
        market: &mut Market<T>,
        clock_obj: &Clock,
        pos: Position<T>,
        min_amount_out: u64,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let coins = sell_no<T>(cfg, market, clock_obj, pos, min_amount_out, ctx);
        sui::transfer::public_transfer(coins, sender(ctx));
    }

    public entry fun entry_add_liquidity<T>(
        cfg: &config::ProtocolConfig<T>,
        market: &mut Market<T>,
        clock_obj: &Clock,
        liquidity: Coin<T>,
        min_lp: u64,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let lp = add_liquidity<T>(cfg, market, clock_obj, liquidity, min_lp, ctx);
        sui::transfer::public_transfer(lp, sender(ctx));
    }

    public entry fun entry_remove_liquidity<T>(
        market: &mut Market<T>,
        lp: LPPosition<T>,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let coin_out = remove_liquidity<T>(market, lp, ctx);
        sui::transfer::public_transfer(coin_out, sender(ctx));
    }

    public entry fun entry_redeem<T>(
        market: &mut Market<T>,
        pos: Position<T>,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let coin_out = redeem<T>(market, pos, ctx);
        sui::transfer::public_transfer(coin_out, sender(ctx));
    }

    #[test_only]
    public fun lp_total<T>(m: &Market<T>): u64 { m.total_lp_shares }

    #[test_only]
    public fun vault_values<T>(m: &Market<T>): (u64, u64) { (balance::value(&m.yes_vault), balance::value(&m.no_vault)) }

    #[test_only]
    public fun lp_shares<T>(lp: &LPPosition<T>): u64 { lp.shares }

    #[test_only]
    public fun position_owner<T>(pos: &Position<T>): address { pos.owner }

    #[test_only]
    public fun destroy_position<T>(pos: Position<T>) {
        let Position { id, market_id: _, owner: _, side_yes: _, shares: _ } = pos;
        sui::object::delete(id);
    }

    #[test_only]
    public fun destroy_lp<T>(lp: LPPosition<T>) {
        let LPPosition { id, market_id: _, shares: _ } = lp;
        sui::object::delete(id);
    }
}
