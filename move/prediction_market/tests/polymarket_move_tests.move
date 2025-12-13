#[test_only]
module prediction_market::polymarket_move_tests {
    use std::unit_test;
    use std::vector as vec;
    use prediction_market::config;
    use prediction_market::liquidity;
    use prediction_market::market;
    use prediction_market::orders;
    use prediction_market::registry;
    use prediction_market::resolution;
    use sui::clock;
    use sui::coin;
    use sui::sui::SUI;
    use sui::tx_context as tx;
    use sui::transfer as tx_transfer;

    fun setup(end_time_ms: u64): (clock::Clock, config::AdminCap, config::ProtocolConfig<SUI>, registry::MarketRegistry, market::Market<SUI>, market::LPPosition<SUI>, tx::TxContext) {
        let mut sys_ctx = tx::new_from_hint(@0x0, 0, 0, 0, 0);
        let mut clock_obj = clock::create_for_testing(&mut sys_ctx);
        clock::set_for_testing(&mut clock_obj, 0);

        let mut admin_ctx = tx::new_from_hint(@0xa, 1, 0, 0, 0);
        let (admin, cfg) = config::create_protocol<SUI>(50, 100, sui::object::id(&clock_obj), &mut admin_ctx);
        let mut registry_obj = registry::new(&mut admin_ctx);
        let liquidity_coin = coin::mint_for_testing<SUI>(1_000_000, &mut admin_ctx);
        let (market_obj, lp) = market::create_market<SUI>(&admin, &cfg, &mut registry_obj, &clock_obj, b"Will the sun shine?".to_string(), end_time_ms, 50, liquidity_coin, &mut admin_ctx);
        (clock_obj, admin, cfg, registry_obj, market_obj, lp, admin_ctx)
    }

    fun user_ctx(sender: address, hint: u64): tx::TxContext {
        tx::new_from_hint(sender, hint, 0, 0, 0)
    }

    fun mint_sui(amount: u64, ctx: &mut tx::TxContext): coin::Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ctx)
    }

    fun burn_sui(c: coin::Coin<SUI>) {
        coin::burn_for_testing<SUI>(c);
    }

    fun cleanup(clock_obj: clock::Clock, admin: config::AdminCap, cfg: config::ProtocolConfig<SUI>, registry_obj: registry::MarketRegistry, market_obj: market::Market<SUI>) {
        clock::destroy_for_testing(clock_obj);
        tx_transfer::public_transfer(admin, @0x1);
        tx_transfer::public_transfer(cfg, @0x1);
        tx_transfer::public_transfer(registry_obj, @0x1);
        tx_transfer::public_transfer(market_obj, @0x1);
    }

    #[test]
    fun test_create_market_registers() {
        let (clock_obj, admin, cfg, registry_obj, market_obj, lp, _ctx) = setup(1_000);
        unit_test::assert_eq!(vec::length(registry::markets(&registry_obj)), 1);
        let mid = sui::object::id(&market_obj);
        assert!(registry::is_active(&registry_obj, mid), 0);
        assert!(market::lp_shares(&lp) > 0, 0);
        market::destroy_lp(lp);
        cleanup(clock_obj, admin, cfg, registry_obj, market_obj);
    }

    #[test]
    fun test_buy_yes_and_no() {
        let (clock_obj, admin, mut cfg, registry_obj, mut market_obj, lp_init, _ctx) = setup(10_000);
        let mut user_ctx = user_ctx(@0xb, 2);
        let payment_yes = mint_sui(10_000, &mut user_ctx);
        let pos_yes = market::buy_yes<SUI>(&mut cfg, &mut market_obj, &clock_obj, @0xb, payment_yes, 1, &mut user_ctx);
        assert!(market::position_shares(&pos_yes) > 0, 0);

        let payment_no = mint_sui(8_000, &mut user_ctx);
        let pos_no = market::buy_no<SUI>(&mut cfg, &mut market_obj, &clock_obj, @0xb, payment_no, 1, &mut user_ctx);
        assert!(market::position_shares(&pos_no) > 0, 0);

        assert!(config::fee_vault_amount(&cfg) > 0, 0);
        market::destroy_position(pos_yes);
        market::destroy_position(pos_no);
        market::destroy_lp(lp_init);
        cleanup(clock_obj, admin, cfg, registry_obj, market_obj);
    }

    #[test, expected_failure(abort_code = 5, location = prediction_market::market)]
    fun test_slippage_failure() {
        let (clock_obj, admin, mut cfg, registry_obj, mut market_obj, lp_init, _ctx) = setup(500);
        let mut user_ctx = user_ctx(@0xc, 3);
        let payment = mint_sui(100, &mut user_ctx);
        let pos = market::buy_yes<SUI>(&mut cfg, &mut market_obj, &clock_obj, @0xc, payment, 10_000_000, &mut user_ctx);
        market::destroy_position(pos);
        market::destroy_lp(lp_init);
        cleanup(clock_obj, admin, cfg, registry_obj, market_obj);
    }

    #[test]
    fun test_add_remove_liquidity() {
        let (clock_obj, admin, cfg, registry_obj, mut market_obj, lp_init, _ctx) = setup(5_000);
        let mut lp_ctx = user_ctx(@0xd, 4);
        let deposit = mint_sui(200_000, &mut lp_ctx);
        let before_lp = market::lp_total(&market_obj);
        let lp_pos = liquidity::add<SUI>(&cfg, &mut market_obj, &clock_obj, deposit, 1, &mut lp_ctx);
        let after_lp = market::lp_total(&market_obj);
        assert!(after_lp > before_lp, 0);
        let withdrawn = liquidity::remove<SUI>(&mut market_obj, lp_pos, &mut lp_ctx);
        assert!(coin::value(&withdrawn) > 0, 0);
        burn_sui(withdrawn);
        let final_lp = market::lp_total(&market_obj);
        unit_test::assert_eq!(final_lp, before_lp);
        market::destroy_lp(lp_init);
        cleanup(clock_obj, admin, cfg, registry_obj, market_obj);
    }

    #[test]
    fun test_limit_order_cancel() {
        let (clock_obj, admin, cfg, registry_obj, mut market_obj, lp_init, _ctx) = setup(10_000);
        let mut user_ctx = user_ctx(@0xe, 5);
        let payment = mint_sui(50_000, &mut user_ctx);
        let expiry = clock::timestamp_ms(&clock_obj) + 5_000;
        let order = orders::create_order<SUI>(&cfg, &mut market_obj, &clock_obj, true, 5_000, 1_000, expiry, payment, &mut user_ctx);
        let order_id = sui::object::id(&order);
        assert!(market::has_order(&market_obj, order_id), 0);
        let refund = orders::cancel_order<SUI>(&mut market_obj, order, &mut user_ctx);
        assert!(coin::value(&refund) > 0, 0);
        burn_sui(refund);
        assert!(!market::has_order(&market_obj, order_id), 0);
        market::destroy_lp(lp_init);
        cleanup(clock_obj, admin, cfg, registry_obj, market_obj);
    }

    #[test]
    fun test_limit_order_fill() {
        let (clock_obj, admin, mut cfg, registry_obj, mut market_obj, lp_init, _ctx) = setup(10_000);
        let mut seller_ctx = user_ctx(@0xf, 6);
        let mut buyer_ctx = user_ctx(@0xe, 7);

        let seller_payment = mint_sui(20_000, &mut seller_ctx);
        let seller_pos = market::buy_yes<SUI>(&mut cfg, &mut market_obj, &clock_obj, @0xf, seller_payment, 1, &mut seller_ctx);

        let payment = mint_sui(50_000, &mut buyer_ctx);
        let expiry = clock::timestamp_ms(&clock_obj) + 5_000;
        let price_bps = 5_000;
        let mut order = orders::create_order<SUI>(&cfg, &mut market_obj, &clock_obj, true, price_bps, market::position_shares(&seller_pos), expiry, payment, &mut buyer_ctx);
        let _order_id = sui::object::id(&order);
        let shares_to_fill = market::position_shares(&seller_pos);
        let cost = price_bps * shares_to_fill / 10_000;
        let (payout, buyer_position) = orders::fill_order<SUI>(&cfg, &clock_obj, &mut market_obj, &mut order, seller_pos, shares_to_fill, &mut seller_ctx);
        unit_test::assert_eq!(coin::value(&payout), cost);
        assert!(market::position_owner(&buyer_position) == @0xe, 0);
        let remaining = orders::cancel_order<SUI>(&mut market_obj, order, &mut buyer_ctx);
        burn_sui(remaining);
        burn_sui(payout);
        market::destroy_position(buyer_position);
        market::destroy_lp(lp_init);
        cleanup(clock_obj, admin, cfg, registry_obj, market_obj);
    }

    #[test, expected_failure(abort_code = 2, location = prediction_market::market)]
    fun test_trading_stops_after_end() {
        let (mut clock_obj, admin, mut cfg, registry_obj, mut market_obj, lp_init, _ctx) = setup(1);
        clock::set_for_testing(&mut clock_obj, 10);
        let mut user_ctx = user_ctx(@0xaa, 8);
        let payment = mint_sui(1_000, &mut user_ctx);
        let pos = market::buy_yes<SUI>(&mut cfg, &mut market_obj, &clock_obj, @0xaa, payment, 1, &mut user_ctx);
        market::destroy_position(pos);
        market::destroy_lp(lp_init);
        cleanup(clock_obj, admin, cfg, registry_obj, market_obj);
    }

    #[test]
    fun test_resolution_flow_and_redeem() {
        let (mut clock_obj, admin, mut cfg, registry_obj, mut market_obj, lp_init, mut admin_ctx) = setup(2_000);
        let mut user_ctx = user_ctx(@0xbb, 9);
        let mut other_ctx = user_ctx(@0xcc, 10);

        let yes_payment = mint_sui(5_000, &mut user_ctx);
        let yes_pos = market::buy_yes<SUI>(&mut cfg, &mut market_obj, &clock_obj, @0xbb, yes_payment, 1, &mut user_ctx);
        let no_payment = mint_sui(5_000, &mut other_ctx);
        let no_pos = market::buy_no<SUI>(&mut cfg, &mut market_obj, &clock_obj, @0xcc, no_payment, 1, &mut other_ctx);

        clock::set_for_testing(&mut clock_obj, 3_000);

        let bond_yes = mint_sui(config::resolution_bond(&cfg), &mut user_ctx);
        resolution::propose_result<SUI>(&cfg, &mut market_obj, &clock_obj, bond_yes, true, &user_ctx);
        let bond_no = mint_sui(config::resolution_bond(&cfg), &mut other_ctx);
        resolution::challenge_result<SUI>(&cfg, &mut market_obj, &clock_obj, bond_no, false, &other_ctx);

        resolution::finalize_result<SUI>(&admin, &mut cfg, &mut market_obj, true, b"", &admin_ctx);
        assert!(market::is_resolved(&market_obj), 0);
        assert!(!market::has_pending(&market_obj), 0);

        let collected = config::collect_fees(&admin, &mut cfg, &mut admin_ctx);
        assert!(coin::value(&collected) >= 2 * config::resolution_bond(&cfg), 0);
        burn_sui(collected);

        let win_coin = market::redeem(&mut market_obj, yes_pos, &mut user_ctx);
        assert!(coin::value(&win_coin) > 0, 0);
        let lose_coin = market::redeem(&mut market_obj, no_pos, &mut other_ctx);
        unit_test::assert_eq!(coin::value(&lose_coin), 0);
        burn_sui(win_coin);
        burn_sui(lose_coin);
        market::destroy_lp(lp_init);
        cleanup(clock_obj, admin, cfg, registry_obj, market_obj);
    }

    #[test]
    fun test_sell_yes_no_before_resolution() {
        let (clock_obj, admin, mut cfg, registry_obj, mut market_obj, lp_init, _ctx) = setup(20_000);
        let mut user_ctx = user_ctx(@0xdd, 11);
        let yes_payment = mint_sui(10_000, &mut user_ctx);
        let yes_pos = market::buy_yes<SUI>(&mut cfg, &mut market_obj, &clock_obj, @0xdd, yes_payment, 1, &mut user_ctx);
        let no_payment = mint_sui(12_000, &mut user_ctx);
        let no_pos = market::buy_no<SUI>(&mut cfg, &mut market_obj, &clock_obj, @0xdd, no_payment, 1, &mut user_ctx);

        let yes_out = market::sell_yes<SUI>(&mut cfg, &mut market_obj, &clock_obj, yes_pos, 1, &mut user_ctx);
        let no_out = market::sell_no<SUI>(&mut cfg, &mut market_obj, &clock_obj, no_pos, 1, &mut user_ctx);
        assert!(coin::value(&yes_out) > 0, 0);
        assert!(coin::value(&no_out) > 0, 0);
        burn_sui(yes_out);
        burn_sui(no_out);
        market::destroy_lp(lp_init);
        cleanup(clock_obj, admin, cfg, registry_obj, market_obj);
    }

    #[test, expected_failure(abort_code = 6, location = prediction_market::config)]
    fun test_fee_upper_bound() {
        // fee_bps > 10_000 should abort
        let mut ctx = tx::new_from_hint(@0xabc, 12, 0, 0, 0);
        let _ = config::create_protocol<SUI>(10_001, 0, sui::object::id(&clock::create_for_testing(&mut ctx)), &mut ctx);
    }

    #[test, expected_failure(abort_code = 2, location = prediction_market::market)]
    fun test_create_market_rejects_past_end() {
        let mut sys_ctx = tx::new_from_hint(@0x0, 13, 0, 0, 0);
        let mut clock_obj = clock::create_for_testing(&mut sys_ctx);
        clock::set_for_testing(&mut clock_obj, 1_000);

        let mut admin_ctx = tx::new_from_hint(@0x1, 14, 0, 0, 0);
        let (admin, cfg) = config::create_protocol<SUI>(50, 100, sui::object::id(&clock_obj), &mut admin_ctx);
        let mut registry_obj = registry::new(&mut admin_ctx);
        let liquidity_coin = coin::mint_for_testing<SUI>(1_000, &mut admin_ctx);
        // end time behind current clock -> abort eended
        let _ = market::create_market<SUI>(&admin, &cfg, &mut registry_obj, &clock_obj, b"Past end".to_string(), 10, 50, liquidity_coin, &mut admin_ctx);
    }

    #[test, expected_failure(abort_code = 4, location = prediction_market::market)]
    fun test_paused_blocks_trading() {
        let (clock_obj, admin, mut cfg, registry_obj, mut market_obj, lp_init, _ctx) = setup(5_000);
        let mut user_ctx = user_ctx(@0xee, 15);
        config::pause(&admin, &mut cfg, &user_ctx);
        let payment = mint_sui(1_000, &mut user_ctx);
        let pos = market::buy_yes<SUI>(&mut cfg, &mut market_obj, &clock_obj, @0xee, payment, 1, &mut user_ctx);
        market::destroy_position(pos);
        market::destroy_lp(lp_init);
        cleanup(clock_obj, admin, cfg, registry_obj, market_obj);
    }
}
