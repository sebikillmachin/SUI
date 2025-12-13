#[allow(lint(public_entry))]
module prediction_market::registry {
    use sui::table::{Table};
    use sui::table;

    /// Shared registry listing all markets for discovery.
    /// Shared to enable permissionless reads by the frontend.
    public struct MarketRegistry has key, store {
        id: UID,
        markets: vector<ID>,
        active: Table<ID, bool>,
    }

    public fun new(ctx: &mut sui::tx_context::TxContext): MarketRegistry {
        MarketRegistry { id: sui::object::new(ctx), markets: vector::empty(), active: table::new(ctx) }
    }

    /// Entry helper to create and share the registry.
    public entry fun entry_new(ctx: &mut sui::tx_context::TxContext) {
        let reg = new(ctx);
        sui::transfer::share_object(reg);
    }

    public fun register(registry: &mut MarketRegistry, market_id: ID) {
        vector::push_back(&mut registry.markets, market_id);
        table::add(&mut registry.active, market_id, true);
    }

    public fun unregister(registry: &mut MarketRegistry, market_id: ID) {
        if (table::remove(&mut registry.active, market_id)) {
            // keep vector for historical discovery
        }
    }

    public fun is_active(registry: &MarketRegistry, market_id: ID): bool {
        table::contains(&registry.active, market_id)
    }

    public fun markets(registry: &MarketRegistry): &vector<ID> {
        &registry.markets
    }
}
