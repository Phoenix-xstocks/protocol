'use client';

import { useReadContract } from 'wagmi';
import { CONTRACTS } from '@/lib/contracts';
import { inkSepolia } from '@/lib/chains';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

export type WaterfallResult = {
  p1Paid: bigint;
  p2Paid: bigint;
  p3Paid: bigint;
  p4Paid: bigint;
  p5Paid: bigint;
  p6Paid: bigint;
  p1FullyPaid: boolean;
};

export function useWaterfallResult() {
  const isDeployed = CONTRACTS.EpochManager.address !== ZERO_ADDRESS;

  const { data, isLoading, error } = useReadContract({
    address: CONTRACTS.EpochManager.address,
    abi: CONTRACTS.EpochManager.abi,
    functionName: 'getLastResult',
    chainId: inkSepolia.id,
    query: {
      enabled: isDeployed,
      refetchInterval: 60_000,
    },
  });

  const result = data as WaterfallResult | undefined;

  return {
    result,
    isLoading,
    error,
  };
}
