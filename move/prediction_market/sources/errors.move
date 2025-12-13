module prediction_market::errors {
    /// Caller lacks the required capability.
    public fun enot_admin(): u64 { 1 }
    /// Market trading has ended.
    public fun eended(): u64 { 2 }
    /// Market already resolved.
    public fun eresolved(): u64 { 3 }
    /// Trading is paused.
    public fun epaused(): u64 { 4 }
    /// Slippage check failed.
    public fun eslippage(): u64 { 5 }
    /// Invalid fee basis points (> 10_000).
    public fun efee(): u64 { 6 }
    /// Not enough liquidity or shares.
    public fun einsufficient(): u64 { 7 }
    /// Expired order or action outside time bounds.
    public fun eexpired(): u64 { 8 }
    /// Order is not registered or already closed.
    public fun eorder(): u64 { 9 }
    /// Resolution already pending.
    public fun epending(): u64 { 10 }
    /// Nothing to redeem.
    public fun enothing(): u64 { 11 }
}
