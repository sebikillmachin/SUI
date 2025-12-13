import { ConnectButton } from '@mysten/dapp-kit';

export const ConnectWallet = () => {
  return (
    <div className="connect-btn">
      <ConnectButton connectText="Connect Wallet" />
    </div>
  );
};
