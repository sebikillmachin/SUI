#[allow(lint(public_entry))]
module prediction_market::orders {
    use prediction_market::config;
    use prediction_market::errors;
    use prediction_market::events;
    use prediction_market::market;
    use sui::balance;
    use sui::balance::Balance;
    use sui::clock;
    use sui::clock::Clock;
    use sui::coin;
    use sui::coin::Coin;
    use sui::tx_context::sender;

    /// Owned limit order with escrowed funds. Owned so users can cancel without shared state.
    public struct LimitOrder<phantom T> has key, store {
        id: UID,
        market_id: ID,
        owner: address,
        side_yes: bool, // true = buy YES, false = buy NO
        price_bps: u64,
        max_shares: u64,
        remaining_shares: u64,
        funds: Balance<T>,
        expiry_ms: u64,
    }

    public fun create_order<T>(
        cfg: &config::ProtocolConfig<T>,
        market_obj: &mut market::Market<T>,
        clock_obj: &Clock,
        side_yes: bool,
        price_bps: u64,
        max_shares: u64,
        expiry_ms: u64,
        payment: Coin<T>,
        ctx: &mut sui::tx_context::TxContext,
    ): LimitOrder<T> {
        market::ensure_open(market_obj, cfg, clock_obj);
        let now = clock::timestamp_ms(clock_obj);
        assert!(expiry_ms > now, errors::eexpired());
        assert!(price_bps > 0 && price_bps <= 10_000, errors::efee());
        let funds = coin::into_balance(payment);
        let order = LimitOrder<T> {
            id: sui::object::new(ctx),
            market_id: market::market_id(market_obj),
            owner: sender(ctx),
            side_yes,
            price_bps,
            max_shares,
            remaining_shares: max_shares,
            funds,
            expiry_ms,
        };
        market::register_order(market_obj, sui::object::id(&order));
        events::emit_order_event(sui::object::id(market_obj), sui::object::id(&order), sender(ctx), 0, side_yes, price_bps, max_shares);
        order
    }

    /// Cancel order and return remaining funds.
    public fun cancel_order<T>(
        market_obj: &mut market::Market<T>,
        order: LimitOrder<T>,
        ctx: &mut sui::tx_context::TxContext,
    ): Coin<T> {
        let order_id = sui::object::id(&order);
        let LimitOrder {
            id,
            market_id,
            owner,
            side_yes,
            price_bps,
            remaining_shares,
            funds,
            expiry_ms: _,
            max_shares: _,
        } = order;
        market::clear_order(market_obj, order_id);
        events::emit_order_event(market_id, order_id, owner, 1, side_yes, price_bps, remaining_shares);
        sui::object::delete(id);
        coin::from_balance(funds, ctx)
    }

    /// Permissionless fill by providing matching position shares (full position).
    /// Returns (payout coin, position minted to buyer (order owner)).
    public fun fill_order<T>(
        cfg: &config::ProtocolConfig<T>,
        clock_obj: &Clock,
        market_obj: &mut market::Market<T>,
        order: &mut LimitOrder<T>,
        seller_pos: market::Position<T>,
        shares_to_sell: u64,
        ctx: &mut sui::tx_context::TxContext,
    ): (Coin<T>, market::Position<T>) {
        market::ensure_open(market_obj, cfg, clock_obj);
        assert!(shares_to_sell == market::position_shares(&seller_pos), errors::einsufficient());
        assert!(order.remaining_shares >= shares_to_sell, errors::eorder());
        let now = clock::timestamp_ms(clock_obj);
        assert!(now <= order.expiry_ms, errors::eexpired());
        assert!(market::position_side(&seller_pos) == order.side_yes, errors::eorder());
        let cost = order.price_bps * shares_to_sell / 10_000;
        assert!(balance::value(&order.funds) >= cost, errors::einsufficient());
        order.remaining_shares = order.remaining_shares - shares_to_sell;
        let payout_bal = balance::split(&mut order.funds, cost);
        let payout = coin::from_balance(payout_bal, ctx);
        let buyer_position = market::transfer_position(seller_pos, order.owner);
        let order_id = sui::object::id(order);
        // keep order registered; owner can cancel remaining funds if any.
        events::emit_order_event(order.market_id, order_id, order.owner, 2, order.side_yes, order.price_bps, shares_to_sell);
        (payout, buyer_position)
    }

    /// Entry wrappers to transfer outputs to the correct parties.
    public entry fun entry_create_order<T>(
        cfg: &config::ProtocolConfig<T>,
        market_obj: &mut market::Market<T>,
        clock_obj: &Clock,
        side_yes: bool,
        price_bps: u64,
        max_shares: u64,
        expiry_ms: u64,
        payment: Coin<T>,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let order = create_order<T>(cfg, market_obj, clock_obj, side_yes, price_bps, max_shares, expiry_ms, payment, ctx);
        sui::transfer::public_transfer(order, sender(ctx));
    }


    public entry fun entry_cancel_order<T>(
        market_obj: &mut market::Market<T>,
        order: LimitOrder<T>,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let refund = cancel_order<T>(market_obj, order, ctx);
        sui::transfer::public_transfer(refund, sender(ctx));
    }

    public entry fun entry_fill_order<T>(
        cfg: &config::ProtocolConfig<T>,
        clock_obj: &Clock,
        market_obj: &mut market::Market<T>,
        order: &mut LimitOrder<T>,
        seller_pos: market::Position<T>,
        shares_to_sell: u64,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let (payout, buyer_pos) = fill_order<T>(cfg, clock_obj, market_obj, order, seller_pos, shares_to_sell, ctx);
        sui::transfer::public_transfer(payout, sender(ctx));
        sui::transfer::public_transfer(buyer_pos, order.owner);
    }
}
