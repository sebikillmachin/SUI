module prediction_market::liquidity {
    use prediction_market::config;
    use prediction_market::market;
    use prediction_market::market::LPPosition;
    use sui::coin::Coin;
    use sui::clock::Clock;

    /// Thin wrapper delegating to market internals to avoid accessing private fields.
    public fun add<T>(
        cfg: &config::ProtocolConfig<T>,
        market_obj: &mut market::Market<T>,
        clock: &Clock,
        deposit: Coin<T>,
        min_lp: u64,
        ctx: &mut TxContext,
    ): LPPosition<T> {
        market::add_liquidity<T>(cfg, market_obj, clock, deposit, min_lp, ctx)
    }

    public fun remove<T>(
        market_obj: &mut market::Market<T>,
        lp: LPPosition<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        market::remove_liquidity<T>(market_obj, lp, ctx)
    }
}
