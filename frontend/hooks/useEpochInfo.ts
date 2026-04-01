'use client';

import { useReadContract } from 'wagmi';
import { CONTRACTS } from '@/lib/contracts';
import { inkSepolia } from '@/lib/chains';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

export function useEpochInfo() {
  const isDeployed = CONTRACTS.EpochManager.address !== ZERO_ADDRESS;

  const queryConfig = {
    enabled: isDeployed,
    refetchInterval: 60_000,
  };

  const contractBase = {
    address: CONTRACTS.EpochManager.address,
    abi: CONTRACTS.EpochManager.abi,
    chainId: inkSepolia.id,
  } as const;

  const {
    data: currentEpoch,
    isLoading: isLoadingEpoch,
  } = useReadContract({
    ...contractBase,
    functionName: 'currentEpoch',
    query: queryConfig,
  });

  const {
    data: epochStartTimestamp,
    isLoading: isLoadingStart,
  } = useReadContract({
    ...contractBase,
    functionName: 'epochStartTimestamp',
    query: queryConfig,
  });

  const {
    data: isEpochReady,
    isLoading: isLoadingReady,
  } = useReadContract({
    ...contractBase,
    functionName: 'isEpochReady',
    query: queryConfig,
  });

  const {
    data: epochDuration,
    isLoading: isLoadingDuration,
  } = useReadContract({
    ...contractBase,
    functionName: 'EPOCH_DURATION',
    query: queryConfig,
  });

  const epochEndTimestamp =
    epochStartTimestamp !== undefined && epochDuration !== undefined
      ? (epochStartTimestamp as bigint) + (epochDuration as bigint)
      : undefined;

  const isLoading =
    isLoadingEpoch || isLoadingStart || isLoadingReady || isLoadingDuration;

  return {
    currentEpoch: currentEpoch as bigint | undefined,
    epochStartTimestamp: epochStartTimestamp as bigint | undefined,
    epochEndTimestamp,
    isEpochReady: isEpochReady as boolean | undefined,
    isLoading,
  };
}
