import { Transaction } from '@mysten/sui/transactions';
import { fromHex } from '@mysten/sui/utils';
import { ids } from '../ids';

const pkg = ids.packageId;

const hexToBytes = (hex?: string): Uint8Array => {
  if (!hex) return new Uint8Array();
  const cleaned = hex.startsWith('0x') ? hex.slice(2) : hex;
  if (cleaned.length === 0) return new Uint8Array();
  return fromHex(cleaned);
};

export const buildBuyYes = (marketId: string, coinType: string, amount: number, minShares: number) => {
  const tx = new Transaction();
  const pay = tx.splitCoins(tx.gas, [tx.pure.u64(amount)])[0];
  tx.moveCall({
    target: `${pkg}::market::entry_buy_yes`,
    typeArguments: [coinType],
    arguments: [tx.object(ids.configId), tx.object(marketId), tx.object(ids.clockId), pay, tx.pure.u64(minShares)],
  });
  return tx;
};

export const buildBuyNo = (marketId: string, coinType: string, amount: number, minShares: number) => {
  const tx = new Transaction();
  const pay = tx.splitCoins(tx.gas, [tx.pure.u64(amount)])[0];
  tx.moveCall({
    target: `${pkg}::market::entry_buy_no`,
    typeArguments: [coinType],
    arguments: [tx.object(ids.configId), tx.object(marketId), tx.object(ids.clockId), pay, tx.pure.u64(minShares)],
  });
  return tx;
};

export const buildAddLiquidity = (marketId: string, coinType: string, amount: number, minLp: number) => {
  const tx = new Transaction();
  const dep = tx.splitCoins(tx.gas, [tx.pure.u64(amount)])[0];
  tx.moveCall({
    target: `${pkg}::market::entry_add_liquidity_balanced`,
    typeArguments: [coinType],
    arguments: [tx.object(ids.configId), tx.object(marketId), tx.object(ids.clockId), dep, tx.pure.u64(minLp)],
  });
  return tx;
};

export const buildRemoveLiquidity = (marketId: string, lpId: string, coinType: string) => {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::market::entry_remove_liquidity`,
    typeArguments: [coinType],
    arguments: [tx.object(marketId), tx.object(lpId)],
  });
  return tx;
};

export const buildRedeem = (marketId: string, positionId: string, coinType: string) => {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::market::entry_redeem`,
    typeArguments: [coinType],
    arguments: [tx.object(marketId), tx.object(positionId)],
  });
  return tx;
};

export const buildSellYes = (marketId: string, coinType: string, positionId: string, minOut: number) => {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::market::entry_sell_yes`,
    typeArguments: [coinType],
    arguments: [tx.object(ids.configId), tx.object(marketId), tx.object(ids.clockId), tx.object(positionId), tx.pure.u64(minOut)],
  });
  return tx;
};

export const buildSellNo = (marketId: string, coinType: string, positionId: string, minOut: number) => {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::market::entry_sell_no`,
    typeArguments: [coinType],
    arguments: [tx.object(ids.configId), tx.object(marketId), tx.object(ids.clockId), tx.object(positionId), tx.pure.u64(minOut)],
  });
  return tx;
};

export const buildCreateOrder = (
  marketId: string,
  coinType: string,
  sideYes: boolean,
  priceBps: number,
  maxShares: number,
  expiryMs: number,
  amount: number,
) => {
  const tx = new Transaction();
  const pay = tx.splitCoins(tx.gas, [tx.pure.u64(amount)])[0];
  tx.moveCall({
    target: `${pkg}::orders::entry_create_order`,
    typeArguments: [coinType],
    arguments: [
      tx.object(ids.configId),
      tx.object(marketId),
      tx.object(ids.clockId),
      tx.pure.bool(sideYes),
      tx.pure.u64(priceBps),
      tx.pure.u64(maxShares),
      tx.pure.u64(expiryMs),
      pay,
    ],
  });
  return tx;
};

export const buildCancelOrder = (marketId: string, orderId: string, coinType: string) => {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::orders::entry_cancel_order`,
    typeArguments: [coinType],
    arguments: [tx.object(marketId), tx.object(orderId)],
  });
  return tx;
};

export const buildFillOrder = (
  marketId: string,
  coinType: string,
  orderId: string,
  sellerPositionId: string,
  sharesToSell: number,
) => {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::orders::entry_fill_order`,
    typeArguments: [coinType],
    arguments: [
      tx.object(ids.configId),
      tx.object(ids.clockId),
      tx.object(marketId),
      tx.object(orderId),
      tx.object(sellerPositionId),
      tx.pure.u64(sharesToSell),
    ],
  });
  return tx;
};

export const buildPropose = (marketId: string, coinType: string, outcomeYes: boolean, bond: number) => {
  const tx = new Transaction();
  const pay = tx.splitCoins(tx.gas, [tx.pure.u64(bond)])[0];
  tx.moveCall({
    target: `${pkg}::resolution::entry_propose_result`,
    typeArguments: [coinType],
    arguments: [tx.object(ids.configId), tx.object(marketId), tx.object(ids.clockId), pay, tx.pure.bool(outcomeYes)],
  });
  return tx;
};

export const buildChallenge = (marketId: string, coinType: string, outcomeYes: boolean, bond: number) => {
  const tx = new Transaction();
  const pay = tx.splitCoins(tx.gas, [tx.pure.u64(bond)])[0];
  tx.moveCall({
    target: `${pkg}::resolution::entry_challenge_result`,
    typeArguments: [coinType],
    arguments: [tx.object(ids.configId), tx.object(marketId), tx.object(ids.clockId), pay, tx.pure.bool(outcomeYes)],
  });
  return tx;
};

export const buildFinalize = (
  marketId: string,
  coinType: string,
  outcomeYes: boolean,
  adminCapId: string,
  pythUpdateHex?: string,
) => {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::resolution::entry_finalize_result`,
    typeArguments: [coinType],
    arguments: [
      tx.object(adminCapId),
      tx.object(ids.configId),
      tx.object(marketId),
      tx.pure.bool(outcomeYes),
      tx.pure.vector('u8', Array.from(hexToBytes(pythUpdateHex))),
    ],
  });
  return tx;
};
