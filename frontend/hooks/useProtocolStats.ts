'use client';

import { useReadContract } from 'wagmi';
import { CONTRACTS } from '@/lib/contracts';
import { inkSepolia } from '@/lib/chains';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

export type ProtocolStatsData = {
  totalNotesCreated: bigint;
  tvl: bigint;
  maxDeposit: bigint;
  reserveBalance: bigint;
  engineUsdcBalance: bigint;
  vaultUsdcBalance: bigint;
  reserveLevel: bigint;
};

export function useProtocolStats(totalNotional: bigint = 0n) {
  const isDeployed = CONTRACTS.ProtocolStats.address !== ZERO_ADDRESS;

  const { data, isLoading, error } = useReadContract({
    address: CONTRACTS.ProtocolStats.address,
    abi: CONTRACTS.ProtocolStats.abi,
    functionName: 'getStats',
    args: [totalNotional],
    chainId: inkSepolia.id,
    query: {
      enabled: isDeployed,
      refetchInterval: 30_000,
    },
  });

  const stats = data as ProtocolStatsData | undefined;

  return {
    stats,
    isLoading,
    error,
  };
}
