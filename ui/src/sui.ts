import { createNetworkConfig } from '@mysten/dapp-kit';
import { getFullnodeUrl } from '@mysten/sui/client';

export const { networkConfig, useNetworkConfig, useNetworkVariable } = createNetworkConfig({
  testnet: { url: getFullnodeUrl('testnet') },
});

export const DEFAULT_NETWORK = 'testnet';
