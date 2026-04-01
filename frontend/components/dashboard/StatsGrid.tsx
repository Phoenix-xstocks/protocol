'use client';

import { StatCard } from '@/components/ui/StatCard';
import { Skeleton } from '@/components/ui/Skeleton';
import { formatUSDC, formatUSDCCompact, formatBps } from '@/lib/format';
import type { ProtocolStatsData } from '@/hooks/useProtocolStats';

interface StatsGridProps {
  stats: ProtocolStatsData | undefined;
  isLoading: boolean;
}

export function StatsGrid({ stats, isLoading }: StatsGridProps) {
  if (isLoading || !stats) {
    return (
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="bg-surface rounded-xl border border-border p-5">
            <Skeleton className="h-4 w-24 mb-2" />
            <Skeleton className="h-8 w-32" />
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
      <StatCard
        label="Total Notes Created"
        value={stats.totalNotesCreated.toString()}
      />
      <StatCard
        label="TVL"
        value={formatUSDCCompact(stats.tvl)}
        prefix="$"
      />
      <StatCard
        label="Max Deposit Available"
        value={formatUSDC(stats.maxDeposit)}
        prefix="$"
      />
      <StatCard
        label="Reserve Level"
        value={formatBps(stats.reserveLevel)}
      />
    </div>
  );
}
