import { useCurrentAccount } from '@mysten/dapp-kit';
import './banners.css';

type Props = {
  expectedChain: `${string}:${string}`;
};

export const NetworkBlocker = ({ expectedChain }: Props) => {
  const account = useCurrentAccount();
  const onTestnet = account?.chains?.includes(expectedChain) ?? true;

  if (!account || onTestnet) return null;

  return (
    <div className="banner warning">
      Switch wallet to Sui Testnet. Trading is disabled until you connect on the expected network.
    </div>
  );
};
