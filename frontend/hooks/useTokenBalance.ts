'use client';

import { useReadContract } from 'wagmi';
import { type Address } from 'viem';
import { CONTRACTS } from '@/lib/contracts';
import { inkSepolia } from '@/lib/chains';

export function useTokenBalance(
  tokenAddress: Address | undefined,
  account: Address | undefined,
) {
  const { data, isLoading } = useReadContract({
    address: tokenAddress!,
    abi: CONTRACTS.USDC.abi,
    functionName: 'balanceOf',
    args: [account!],
    chainId: inkSepolia.id,
    query: {
      enabled: !!tokenAddress && !!account,
      refetchInterval: 10_000,
    },
  });

  return {
    balance: data as bigint | undefined,
    isLoading,
  };
}
