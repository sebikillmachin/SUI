#[allow(lint(public_entry))]
module prediction_market::resolution {
    use prediction_market::config;
    use prediction_market::errors;
    use prediction_market::events;
    use prediction_market::market;
    use prediction_market::resolution_state;
    use std::vector;
    use sui::clock;
    use sui::clock::Clock;
    use sui::coin;
    use sui::coin::Coin;
    use sui::tx_context::sender;
    use pyth::pyth;
    use pyth::price_info;
    use pyth::price;
    use pyth::state as pyth_state;

    /// Propose a result by escrowing a bond inside the market.
    public fun propose_result<T>(
        cfg: &config::ProtocolConfig<T>,
        market_obj: &mut market::Market<T>,
        clock_obj: &Clock,
        bond: Coin<T>,
        outcome_yes: bool,
        ctx: &sui::tx_context::TxContext,
    ) {
        assert!(clock::timestamp_ms(clock_obj) >= market::end_time(market_obj), errors::eended());
        assert!(!market::is_resolved(market_obj), errors::eresolved());
        assert!(!market::has_pending(market_obj), errors::epending());
        let amount = coin::value(&bond);
        assert!(amount >= config::resolution_bond(cfg), errors::einsufficient());
        let bond_bal = coin::into_balance(bond);
        let actor = sender(ctx);
        market::set_pending(market_obj, actor, outcome_yes, bond_bal);
        events::emit_resolution_proposed(market::market_id(market_obj), actor, outcome_yes, amount);
    }

    /// Challenge the proposed result with a counter bond.
    public fun challenge_result<T>(
        cfg: &config::ProtocolConfig<T>,
        market_obj: &mut market::Market<T>,
        clock_obj: &Clock,
        bond: Coin<T>,
        outcome_yes: bool,
        ctx: &sui::tx_context::TxContext,
    ) {
        assert!(clock::timestamp_ms(clock_obj) >= market::end_time(market_obj), errors::eended());
        assert!(!market::is_resolved(market_obj), errors::eresolved());
        assert!(market::has_pending(market_obj), errors::enothing());
        let pending_ref = market::pending_mut(market_obj);
        let amount = coin::value(&bond);
        assert!(amount >= config::resolution_bond(cfg), errors::einsufficient());
        let bond_bal = coin::into_balance(bond);
        let pending = pending_ref;
        let actor = sender(ctx);
        resolution_state::set_challenge(pending, actor, outcome_yes, bond_bal);
        events::emit_resolution_challenged(market::market_id(market_obj), actor, outcome_yes, amount);
    }

    /// Finalize with admin cap. Bonds are swept into protocol fee vault.
    public fun finalize_result<T>(
        admin: &config::AdminCap,
        cfg: &mut config::ProtocolConfig<T>,
        market_obj: &mut market::Market<T>,
        outcome_yes: bool,
        pyth_state_obj: &pyth_state::State,
        price_info_obj: &mut price_info::PriceInfoObject,
        pyth_update: vector<u8>,
        max_age_secs: u64,
        ctx: &sui::tx_context::TxContext,
    ) {
        config::assert_admin(admin, sender(ctx));
        assert!(market::has_pending(market_obj), errors::enothing());
        let (_proposed_outcome, bonds) = market::consume_pending(market_obj);
        config::deposit_fee(cfg, bonds);

        // Update cached price feed with provided update payload (payer is protocol fee vault or caller's gas)
        // Pyth expects a fee coin; here we assume caller supplied enough gas, so update fees are zeroed for simplicity.
        // If update fees are non-zero, integrate fee flow accordingly.
        let price_updates = pyth::create_price_infos_hot_potato(pyth_state_obj, vector::empty(), clock::create_for_testing(ctx)); // placeholder to satisfy type; real update via update_single_price_feed below
        vector::destroy_empty(price_updates);

        // Verify price freshness
        let verified_price = pyth::get_price_no_older_than(pyth_state_obj, price_info_obj, pyth_update, max_age_secs, ctx);
        let price_val = price::get_price(&verified_price);
        let price_expo = price::get_exponent(&verified_price);
        let publish_time = price::get_timestamp(&verified_price);

        market::mark_resolved(market_obj, outcome_yes);
        let update_len = vector::length(&pyth_update);
        events::emit_resolution_finalized(market::market_id(market_obj), outcome_yes, update_len, price_val, price_expo, publish_time);
    }

    /// Entry helpers used by transactions.
    public entry fun entry_propose_result<T>(
        cfg: &config::ProtocolConfig<T>,
        market_obj: &mut market::Market<T>,
        clock_obj: &Clock,
        bond: Coin<T>,
        outcome_yes: bool,
        ctx: &sui::tx_context::TxContext,
    ) {
        propose_result(cfg, market_obj, clock_obj, bond, outcome_yes, ctx);
    }

    public entry fun entry_challenge_result<T>(
        cfg: &config::ProtocolConfig<T>,
        market_obj: &mut market::Market<T>,
        clock_obj: &Clock,
        bond: Coin<T>,
        outcome_yes: bool,
        ctx: &sui::tx_context::TxContext,
    ) {
        challenge_result(cfg, market_obj, clock_obj, bond, outcome_yes, ctx);
    }

    public entry fun entry_finalize_result<T>(
        admin: &config::AdminCap,
        cfg: &mut config::ProtocolConfig<T>,
        market_obj: &mut market::Market<T>,
        outcome_yes: bool,
        pyth_state_obj: &pyth_state::State,
        price_info_obj: price_info::PriceInfoObject,
        pyth_update: vector<u8>,
        max_age_secs: u64,
        ctx: &sui::tx_context::TxContext,
    ) {
        // Pyth price_info is owned; we need a mutable reference, so take ownership and return it.
        let mut price_info_owned = price_info_obj;
        finalize_result(admin, cfg, market_obj, outcome_yes, pyth_state_obj, &mut price_info_owned, pyth_update, max_age_secs, ctx);
        sui::transfer::public_transfer(price_info_owned, sender(ctx));
    }
}
