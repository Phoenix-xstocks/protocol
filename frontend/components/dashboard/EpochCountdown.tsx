'use client';

import { CountdownTimer } from '@/components/ui/CountdownTimer';
import { Badge } from '@/components/ui/Badge';
import { Skeleton } from '@/components/ui/Skeleton';

interface EpochCountdownProps {
  currentEpoch: number;
  epochEndTimestamp: number;
  isEpochReady: boolean;
  isLoading: boolean;
}

export function EpochCountdown({ currentEpoch, epochEndTimestamp, isEpochReady, isLoading }: EpochCountdownProps) {
  if (isLoading) {
    return (
      <div className="bg-surface rounded-xl border border-border p-6">
        <Skeleton className="h-6 w-24 mb-4" />
        <Skeleton className="h-8 w-40 mb-3" />
        <Skeleton className="h-5 w-16" />
      </div>
    );
  }

  return (
    <div className="bg-surface rounded-xl border border-border p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-white">
          Epoch #{currentEpoch}
        </h3>
        {isEpochReady && (
          <Badge
            label="Ready"
            color="text-gain"
            bgColor="bg-gain/10"
          />
        )}
      </div>
      <CountdownTimer
        targetTimestamp={epochEndTimestamp}
        label="Ends in"
        className="text-xl"
      />
    </div>
  );
}
