# UI (Vite + React + dapp-kit)

Sui testnet-only frontend for the on-chain prediction market. No backend or indexer is required; reads come straight from Sui RPC, writes go through the connected wallet.

## Quick start
```
cd ui
npm install
npm run dev   # start local dev server on http://localhost:5173
npm run build # typecheck + production bundle
```

## Environment (.env)
Fill with the on-chain IDs from your deployed Move package:
```
VITE_PACKAGE_ID=<PACKAGE_ID>
VITE_CONFIG_ID=<CONFIG_ID>
VITE_REGISTRY_ID=<REGISTRY_ID>
VITE_CLOCK_ID=0x6
# Optional admin actions
VITE_ADMIN_CAP_ID=<ADMIN_CAP_ID>
# Optional extra wrapped coins on Sui so they appear in the token list
VITE_TOKEN_WSOL=<WSOL_COIN_TYPE>
VITE_TOKEN_WETH=<WETH_COIN_TYPE>
VITE_TOKEN_WBTC=<WBTC_COIN_TYPE>
VITE_TOKEN_USDC=<USDC_COIN_TYPE>
```

Coins are per-market: to trade in another asset, create a market parameterized with that coin type and make sure you hold that coin on Sui.

## Trading and resolution notes
- Quick trade buys YES/NO with the selected market coin; inputs are clamped to non-negative values.
- Portfolio lets you sell a position back to the pool before resolution (burns the position, returns coins) and cancel open limit orders.
- Admin finalize can take a Pyth price update payload (hex). Leave empty only for testing.

## UX polish
- Always-visible testnet banner and network blocker if the wallet is not on Sui Testnet.
- Markets are discovered from the shared registry (no hardcoded IDs).
- Portfolio surfaces positions, LP shares, and limit orders with their coin type so each transaction uses the right type argument.
- Toasts on success/failure, buttons disable when wallet is missing/gasless/AdminCapless, and basic validation on admin forms.

## Why this UI is fully on-chain
- Reads: direct Sui RPC queries for registry, markets, positions, LP, and limit orders; no backend or indexer.
- Writes: transactions are built client-side and signed in the wallet via @mysten/dapp-kit (buy/sell, liquidity, limit orders, redeem).
- Admin: propose/challenge/finalize call the Move entry functions with AdminCap, bond amount, and optional Pyth bytes. If the wallet lacks permissions or SUI for gas/bonds, the transaction fails; there is no mock path.

## Admin-only cards
- Resolution (propose/challenge): post or dispute an outcome (YES/NO). Needs AdminCap and the protocol resolution bond.
- Finalize (admin): set the final outcome; optional Pyth update bytes for on-chain proof. Needs AdminCap.
