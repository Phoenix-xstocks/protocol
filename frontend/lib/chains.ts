import { defineChain } from 'viem';

export const inkSepolia = defineChain({
  id: 763373,
  name: 'Ink Sepolia',
  nativeCurrency: {
    name: 'Ether',
    symbol: 'ETH',
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: ['https://rpc-gel-sepolia.inkonchain.com'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Ink Sepolia Explorer',
      url: 'https://explorer-sepolia.inkonchain.com',
    },
  },
  testnet: true,
});
