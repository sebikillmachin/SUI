module prediction_market::events {
    use std::string::String;
    use sui::event;

    /// Emitted when a new market is created.
    public struct MarketCreated has copy, drop {
        market_id: ID,
        registry_id: ID,
        question: String,
        end_time_ms: u64,
    }

    /// Emitted on trades.
    public struct Trade has copy, drop {
        market_id: ID,
        buyer: address,
        side_yes: bool,
        input: u64,
        shares_out: u64,
        fee_paid: u64,
    }

    /// Emitted on sells (burning shares back into the pool).
    public struct Sell has copy, drop {
        market_id: ID,
        seller: address,
        side_yes: bool,
        shares_in: u64,
        amount_out: u64,
        fee_paid: u64,
    }

    /// Emitted on LP actions.
    public struct LiquidityChanged has copy, drop {
        market_id: ID,
        lp_owner: address,
        added: bool,
        yes_delta: u64,
        no_delta: u64,
        lp_shares: u64,
    }

    /// Emitted for limit order lifecycle.
    public struct OrderEvent has copy, drop {
        market_id: ID,
        order_id: ID,
        owner: address,
        action: u8, // 0=create,1=cancel,2=fill
        side_yes: bool,
        price_bps: u64,
        shares: u64,
    }

    /// Emitted for resolution updates.
    public struct ResolutionProposed has copy, drop {
        market_id: ID,
        proposer: address,
        outcome_yes: bool,
        bond: u64,
    }

    public struct ResolutionChallenged has copy, drop {
        market_id: ID,
        challenger: address,
        outcome_yes: bool,
        bond: u64,
    }

    public struct ResolutionFinalized has copy, drop {
        market_id: ID,
        outcome_yes: bool,
        /// Length of the Pyth price update payload supplied in the resolve tx (pull-model attestation).
        pyth_update_len: u64,
        /// Verified price (if provided via Pyth) at resolution time, scaled with exponent.
        price: u64,
        expo: i32,
        publish_time: u64,
    }

    public fun emit_market_created(market_id: ID, registry_id: ID, question: String, end_time_ms: u64) {
        event::emit(MarketCreated { market_id, registry_id, question, end_time_ms });
    }

    public fun emit_trade(market_id: ID, buyer: address, side_yes: bool, input: u64, shares_out: u64, fee_paid: u64) {
        event::emit(Trade { market_id, buyer, side_yes, input, shares_out, fee_paid });
    }

    public fun emit_sell(market_id: ID, seller: address, side_yes: bool, shares_in: u64, amount_out: u64, fee_paid: u64) {
        event::emit(Sell { market_id, seller, side_yes, shares_in, amount_out, fee_paid });
    }

    public fun emit_liquidity(market_id: ID, lp_owner: address, added: bool, yes_delta: u64, no_delta: u64, lp_shares: u64) {
        event::emit(LiquidityChanged { market_id, lp_owner, added, yes_delta, no_delta, lp_shares });
    }

    public fun emit_order_event(market_id: ID, order_id: ID, owner: address, action: u8, side_yes: bool, price_bps: u64, shares: u64) {
        event::emit(OrderEvent { market_id, order_id, owner, action, side_yes, price_bps, shares });
    }

    public fun emit_resolution_proposed(market_id: ID, proposer: address, outcome_yes: bool, bond: u64) {
        event::emit(ResolutionProposed { market_id, proposer, outcome_yes, bond });
    }

    public fun emit_resolution_challenged(market_id: ID, challenger: address, outcome_yes: bool, bond: u64) {
        event::emit(ResolutionChallenged { market_id, challenger, outcome_yes, bond });
    }

    public fun emit_resolution_finalized(market_id: ID, outcome_yes: bool, pyth_update_len: u64, price: u64, expo: i32, publish_time: u64) {
        event::emit(ResolutionFinalized { market_id, outcome_yes, pyth_update_len, price, expo, publish_time });
    }
}
