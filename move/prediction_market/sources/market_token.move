module prediction_market::market_token {
    use sui::coin;
    use sui::coin::{Coin, TreasuryCap};
    use sui::coin_registry;

    /// Utility token for rewards/testing. Not central to the AMM but useful in tests.
    public struct MarketToken has drop, store {}

    /// Faucet cap to allow controlled minting on testnet.
    public struct FaucetCap has key, store {
        id: UID,
        treasury: TreasuryCap<MarketToken>,
    }

    public fun create_token(ctx: &mut TxContext): (FaucetCap, coin_registry::MetadataCap<MarketToken>) {
        let (builder, treasury) = coin_registry::new_currency_with_otw(
            MarketToken {},
            9,
            b"PMT".to_string(),
            b"Prediction Market Token".to_string(),
            b"Utility token for tests".to_string(),
            b"https://example.com/pmt.png".to_string(),
            ctx,
        );
        let metadata_cap = coin_registry::finalize(builder, ctx);
        (FaucetCap { id: sui::object::new(ctx), treasury }, metadata_cap)
    }

    public fun mint(cap: &mut FaucetCap, amount: u64, ctx: &mut TxContext): Coin<MarketToken> {
        coin::mint(&mut cap.treasury, amount, ctx)
    }

    public fun burn(cap: &mut FaucetCap, amount: Coin<MarketToken>): u64 {
        coin::burn(&mut cap.treasury, amount)
    }
}
