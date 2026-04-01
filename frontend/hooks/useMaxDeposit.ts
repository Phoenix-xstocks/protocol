'use client';

import { useReadContract } from 'wagmi';
import { type Address } from 'viem';
import { CONTRACTS } from '@/lib/contracts';
import { inkSepolia } from '@/lib/chains';

export function useMaxDeposit(receiver: Address | undefined) {
  const { data, isLoading } = useReadContract({
    address: CONTRACTS.XYieldVault.address,
    abi: CONTRACTS.XYieldVault.abi,
    functionName: 'maxDeposit',
    args: [receiver!],
    chainId: inkSepolia.id,
    query: {
      enabled: !!receiver,
      refetchInterval: 60_000,
    },
  });

  return {
    maxDeposit: data as bigint | undefined,
    isLoading,
  };
}
