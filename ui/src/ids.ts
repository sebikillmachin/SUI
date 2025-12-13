const requireEnv = (key: string): string => {
  const value = import.meta.env[key];
  if (!value) {
    throw new Error(`Missing env ${key}. Please set it in .env`);
  }
  return value as string;
};

export const ids = {
  packageId: requireEnv('VITE_PACKAGE_ID'),
  registryId: requireEnv('VITE_REGISTRY_ID'),
  configId: requireEnv('VITE_CONFIG_ID'),
  clockId: import.meta.env.VITE_CLOCK_ID ?? '0x6',
  adminCapId: import.meta.env.VITE_ADMIN_CAP_ID ?? '',
};

export type EnvIds = typeof ids;

export type TokenConfig = {
  type: string;
  symbol: string;
  decimals: number;
};

// Default SUI plus optional tokens provided via env (VITE_TOKEN_WBTC, etc.)
export const tokens: TokenConfig[] = [
  { type: '0x2::sui::SUI', symbol: 'SUI', decimals: 9 },
  ...(import.meta.env.VITE_TOKEN_WBTC
    ? [{ type: import.meta.env.VITE_TOKEN_WBTC as string, symbol: 'wBTC', decimals: 8 }]
    : []),
  ...(import.meta.env.VITE_TOKEN_WETH
    ? [{ type: import.meta.env.VITE_TOKEN_WETH as string, symbol: 'wETH', decimals: 8 }]
    : []),
  ...(import.meta.env.VITE_TOKEN_USDC
    ? [{ type: import.meta.env.VITE_TOKEN_USDC as string, symbol: 'USDC', decimals: 6 }]
    : []),
  ...(import.meta.env.VITE_TOKEN_WSOL
    ? [{ type: import.meta.env.VITE_TOKEN_WSOL as string, symbol: 'wSOL', decimals: 9 }]
    : []),
];
