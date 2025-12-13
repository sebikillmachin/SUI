#[allow(lint(public_entry))]
module prediction_market::config {
    use prediction_market::errors;
    use sui::balance;
    use sui::balance::Balance;
    use sui::coin;
    use sui::tx_context::sender;

    /// Admin capability kept owned by deployer for privileged actions.
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Shared protocol config, generic over coin type T so fees can be denominated in the market coin.
    /// Shared so everyone can read fee settings and pause state on-chain.
    public struct ProtocolConfig<phantom T> has key, store {
        id: UID,
        fee_bps: u64,
        resolution_bond: u64,
        paused: bool,
        fee_vault: Balance<T>,
        clock_id: ID,
    }

    /// Create protocol objects (AdminCap owned, ProtocolConfig<T> to be shared).
    public fun create_protocol<T>(fee_bps: u64, resolution_bond: u64, clock_id: ID, ctx: &mut sui::tx_context::TxContext): (AdminCap, ProtocolConfig<T>) {
        assert!(fee_bps <= 10_000, errors::efee());
        (
            AdminCap { id: sui::object::new(ctx) },
            ProtocolConfig<T> {
                id: sui::object::new(ctx),
                fee_bps,
                resolution_bond,
                paused: false,
                fee_vault: balance::zero<T>(),
                clock_id,
            },
        )
    }

    public fun assert_admin(_cap: &AdminCap, _who: address) {
        // Presence of the cap is the proof; kept for clarity.
    }

    public fun pause<T>(cap: &AdminCap, cfg: &mut ProtocolConfig<T>, ctx: &sui::tx_context::TxContext) {
        assert_admin(cap, sender(ctx));
        cfg.paused = true;
    }

    public fun unpause<T>(cap: &AdminCap, cfg: &mut ProtocolConfig<T>, ctx: &sui::tx_context::TxContext) {
        assert_admin(cap, sender(ctx));
        cfg.paused = false;
    }

    public fun set_fee<T>(cap: &AdminCap, cfg: &mut ProtocolConfig<T>, new_fee_bps: u64, ctx: &sui::tx_context::TxContext) {
        assert!(new_fee_bps <= 10_000, errors::efee());
        assert_admin(cap, sender(ctx));
        cfg.fee_bps = new_fee_bps;
    }

    public fun set_resolution_bond<T>(cap: &AdminCap, cfg: &mut ProtocolConfig<T>, bond: u64, ctx: &sui::tx_context::TxContext) {
        assert_admin(cap, sender(ctx));
        cfg.resolution_bond = bond;
    }

    public fun collect_fees<T>(cap: &AdminCap, cfg: &mut ProtocolConfig<T>, ctx: &mut sui::tx_context::TxContext): coin::Coin<T> {
        assert_admin(cap, sender(ctx));
        let bal = balance::withdraw_all(&mut cfg.fee_vault);
        coin::from_balance(bal, ctx)
    }

    /// Called by markets to move fees into global vault.
    public fun deposit_fee<T>(cfg: &mut ProtocolConfig<T>, fee: Balance<T>) {
        balance::join(&mut cfg.fee_vault, fee);
    }

    public fun fee_bps<T>(cfg: &ProtocolConfig<T>): u64 {
        cfg.fee_bps
    }

    public fun resolution_bond<T>(cfg: &ProtocolConfig<T>): u64 {
        cfg.resolution_bond
    }

    public fun is_paused<T>(cfg: &ProtocolConfig<T>): bool {
        cfg.paused
    }

    public fun clock_id<T>(cfg: &ProtocolConfig<T>): ID {
        cfg.clock_id
    }

    #[test_only]
    public fun fee_vault_amount<T>(cfg: &ProtocolConfig<T>): u64 {
        balance::value(&cfg.fee_vault)
    }

    /// Entry helper: share the protocol config and hand AdminCap to publisher.
    public entry fun entry_create_protocol<T>(fee_bps: u64, resolution_bond: u64, clock_id: ID, ctx: &mut sui::tx_context::TxContext) {
        let sender_addr = sender(ctx);
        let (cap, cfg) = create_protocol<T>(fee_bps, resolution_bond, clock_id, ctx);
        sui::transfer::public_transfer(cap, sender_addr);
        sui::transfer::share_object(cfg);
    }
}
