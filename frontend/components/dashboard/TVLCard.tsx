'use client';

import { MonoNumber } from '@/components/ui/MonoNumber';
import { Skeleton } from '@/components/ui/Skeleton';
import { formatUSDC } from '@/lib/format';

interface TVLCardProps {
  tvl: bigint;
  vaultBalance: bigint;
  engineBalance: bigint;
  isLoading: boolean;
}

export function TVLCard({ tvl, vaultBalance, engineBalance, isLoading }: TVLCardProps) {
  if (isLoading) {
    return (
      <div className="bg-surface rounded-xl border border-border border-l-4 border-l-gain p-6">
        <Skeleton className="h-4 w-32 mb-3" />
        <Skeleton className="h-10 w-48 mb-4" />
        <div className="flex gap-6">
          <Skeleton className="h-4 w-36" />
          <Skeleton className="h-4 w-36" />
        </div>
      </div>
    );
  }

  return (
    <div className="bg-surface rounded-xl border border-border border-l-4 border-l-gain p-6">
      <p className="text-sm text-muted mb-2">Total Value Locked</p>
      <MonoNumber
        value={formatUSDC(tvl)}
        prefix="$"
        size="xl"
        className="text-white"
      />
      <div className="flex gap-6 mt-4 text-sm">
        <div>
          <span className="text-muted">Vault: </span>
          <span className="font-mono tabular-nums text-white">
            ${formatUSDC(vaultBalance)}
          </span>
        </div>
        <div>
          <span className="text-muted">Engine: </span>
          <span className="font-mono tabular-nums text-white">
            ${formatUSDC(engineBalance)}
          </span>
        </div>
      </div>
    </div>
  );
}
