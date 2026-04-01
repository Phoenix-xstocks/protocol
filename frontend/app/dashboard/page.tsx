'use client';

import { PageContainer } from '@/components/layout/PageContainer';
import { TVLCard } from '@/components/dashboard/TVLCard';
import { StatsGrid } from '@/components/dashboard/StatsGrid';
import { EpochCountdown } from '@/components/dashboard/EpochCountdown';
import { ReserveHealthGauge } from '@/components/dashboard/ReserveHealthGauge';
import { WaterfallChart } from '@/components/dashboard/WaterfallChart';
import { useProtocolStats } from '@/hooks/useProtocolStats';
import { useEpochInfo } from '@/hooks/useEpochInfo';
import { useWaterfallResult } from '@/hooks/useWaterfallResult';

export default function DashboardPage() {
  const { stats, isLoading: isLoadingStats } = useProtocolStats();
  const {
    currentEpoch,
    epochEndTimestamp,
    isEpochReady,
    isLoading: isLoadingEpoch,
  } = useEpochInfo();
  const { result, isLoading: isLoadingWaterfall } = useWaterfallResult();

  return (
    <PageContainer title="Protocol Dashboard" subtitle="Real-time protocol metrics and epoch status">
      <div className="space-y-6">
        {/* TVL - full width */}
        <TVLCard
          tvl={stats?.tvl ?? 0n}
          vaultBalance={stats?.vaultUsdcBalance ?? 0n}
          engineBalance={stats?.engineUsdcBalance ?? 0n}
          isLoading={isLoadingStats}
        />

        {/* Stats grid */}
        <StatsGrid stats={stats} isLoading={isLoadingStats} />

        {/* Epoch + Reserve side by side */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <EpochCountdown
            currentEpoch={Number(currentEpoch ?? 0n)}
            epochEndTimestamp={Number(epochEndTimestamp ?? 0n)}
            isEpochReady={isEpochReady ?? false}
            isLoading={isLoadingEpoch}
          />
          <ReserveHealthGauge
            reserveLevel={stats?.reserveLevel ?? 0n}
            isLoading={isLoadingStats}
          />
        </div>

        {/* Waterfall chart - full width */}
        <WaterfallChart
          result={result}
          isLoading={isLoadingWaterfall}
        />
      </div>
    </PageContainer>
  );
}
