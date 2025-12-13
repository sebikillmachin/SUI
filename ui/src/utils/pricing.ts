export const toFixed = (n: number, decimals = 2) => Number(n.toFixed(decimals));

export const priceYesBps = (yesVault: bigint, noVault: bigint) => {
  const total = yesVault + noVault;
  if (total === 0n) return 5000;
  return Number((yesVault * 10_000n) / total);
};

export const priceNoBps = (yesVault: bigint, noVault: bigint) => 10_000 - priceYesBps(yesVault, noVault);

export const formatSui = (value: bigint) => `${Number(value) / 1_000_000_000} SUI`;
