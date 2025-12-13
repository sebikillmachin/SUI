# Sui Prediction Market (Testnet Demo)

On-chain prediction market with Move contracts and a React + TypeScript frontend (Vite + dapp-kit). No backend or indexer required: reads come from Sui RPC, writes are signed in the wallet.

## Prerequisites
- Sui CLI (latest testnet build)
- Node.js 18+ and npm

## Move package
Path: `move/prediction_market`

Build and test:
```
cd move/prediction_market
sui move build
sui move test
```

### Publish and capture IDs
```bash
cd move/prediction_market
sui client publish --gas-budget 200000000
```
From the publish output note:
- `PACKAGE_ID`
- For initial setup, run:
  - Create protocol (shared):  
    ```bash
    sui client call --package <PACKAGE_ID> --module config --function entry_create_protocol \
      --args <fee_bps> <resolution_bond> <clock_id> \
      --gas-budget 200000000
    ```
    This returns an `AdminCap` (owned) and shares a `ProtocolConfig` (shared). `clock_id` is usually `0x6` on testnet.
  - Create registry (shared):  
    ```bash
    sui client call --package <PACKAGE_ID> --module registry --function entry_new --gas-budget 50000000
    ```
  - Create a market with initial liquidity using the AdminCap, shared ProtocolConfig, and shared MarketRegistry. Example:  
    ```bash
    sui client call --package <PACKAGE_ID> --module market --function entry_create_market \
      --args <ADMIN_CAP_ID> <CONFIG_ID> <REGISTRY_ID> 0x6 \
      "Will it be sunny tomorrow?" <end_time_ms> <fee_bps> <liquidity_coin_object> \
      --gas-budget 200000000
    ```
  - Pre-resolution selling back into the pool (burn shares for coins):  
    ```bash
    sui client call --package <PACKAGE_ID> --module market --function entry_sell_yes \
      --args <CONFIG_ID> <MARKET_ID> 0x6 <POSITION_ID> <min_amount_out> --gas-budget 80000000
    ```
    (`entry_sell_no` for NO positions.)

Record the shared object IDs for the UI environment:
- `VITE_PACKAGE_ID=<PACKAGE_ID>`
- `VITE_CONFIG_ID=<CONFIG_ID>` (shared ProtocolConfig)
- `VITE_REGISTRY_ID=<REGISTRY_ID>` (shared MarketRegistry)
- `VITE_CLOCK_ID=0x6` (default on testnet)
- Optional admin actions: `VITE_ADMIN_CAP_ID=<ADMIN_CAP_ID>`

## Frontend (.env)
Create `ui/.env`:
```
VITE_PACKAGE_ID=<PACKAGE_ID>
VITE_CONFIG_ID=<CONFIG_ID>
VITE_REGISTRY_ID=<REGISTRY_ID>
VITE_CLOCK_ID=0x6
# Optional
VITE_ADMIN_CAP_ID=<ADMIN_CAP_ID>
# Optional additional test tokens (wrapped on Sui) to make them selectable in the UI
# Provide the full coin type, e.g. 0x...::coin::T
VITE_TOKEN_WSOL=<WSOL_COIN_TYPE>
VITE_TOKEN_WETH=<WETH_COIN_TYPE>
VITE_TOKEN_WBTC=<WBTC_COIN_TYPE>
VITE_TOKEN_USDC=<USDC_COIN_TYPE>
```
The UI discovers markets from the shared registry. Markets use the coin type they were created with, so to trade with another asset you must create a market parameterized with that coin type and hold that coin on Sui.

### Oracle resolution (Pyth pull-style)
- Resolution finalize entry accepts a `vector<u8>` payload (e.g., a Pyth price update) so the proof/update is carried inside the resolve transaction:
  ```bash
  sui client call --package <PACKAGE_ID> --module resolution --function entry_finalize_result \
    --args <ADMIN_CAP_ID> <CONFIG_ID> <MARKET_ID> <bool_outcome_yes> <pyth_update_bytes> \
    --type-args <COIN_TYPE> --gas-budget 80000000
  ```
- If you do not have an update, pass an empty byte vector (`0x`), but for production provide the real Pyth attestation bytes.

## Frontend commands
```bash
cd ui
npm install
npm run dev     # local dev
npm run build   # production build
```
The app connects to Sui testnet by default and blocks transactions if the wallet is not on testnet.

## Safety
Testnet-only demo. No real money or real-value payouts. Use at your own risk.
