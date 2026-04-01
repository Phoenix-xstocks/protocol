'use client';

import { useProtocolStats } from '@/hooks/useProtocolStats';
import { StatCard } from '@/components/ui/StatCard';
import { Skeleton } from '@/components/ui/Skeleton';
import { formatUSDCCompact, formatBps } from '@/lib/format';

export function LiveStats() {
  const { stats, isLoading } = useProtocolStats();

  return (
    <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
      <h2 className="text-3xl font-bold text-white text-center mb-14">
        Protocol at a Glance
      </h2>

      {isLoading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-28 rounded-xl" />
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          <StatCard
            label="Total Value Locked"
            value={stats ? formatUSDCCompact(stats.tvl) : '--'}
            prefix="$"
          />
          <StatCard
            label="Active Notes"
            value={stats ? stats.totalNotesCreated.toString() : '--'}
          />
          <StatCard
            label="Reserve Health"
            value={stats ? formatBps(stats.reserveLevel) : '--'}
          />
          <StatCard
            label="Max Capacity"
            value={stats ? formatUSDCCompact(stats.maxDeposit) : '--'}
            prefix="$"
          />
        </div>
      )}
    </section>
  );
}
