'use client';

import { Skeleton } from '@/components/ui/Skeleton';
import { formatBps } from '@/lib/format';

interface ReserveHealthGaugeProps {
  reserveLevel: bigint;
  isLoading: boolean;
}

function getGaugeColor(bps: number): string {
  if (bps < 300) return '#ef4444';
  if (bps < 500) return '#eab308';
  return '#22c55e';
}

export function ReserveHealthGauge({ reserveLevel, isLoading }: ReserveHealthGaugeProps) {
  if (isLoading) {
    return (
      <div className="bg-surface rounded-xl border border-border p-6 flex flex-col items-center">
        <Skeleton className="h-4 w-28 mb-4" />
        <Skeleton className="h-32 w-48 rounded-t-full" />
      </div>
    );
  }

  const bps = Number(reserveLevel);
  const fillPercent = Math.min(bps / 1000, 1);
  const color = getGaugeColor(bps);

  // SVG semicircular gauge
  // Arc from 180deg to 0deg (left to right along top)
  const radius = 70;
  const cx = 80;
  const cy = 80;
  const strokeWidth = 12;

  // Full arc length for semicircle
  const circumference = Math.PI * radius;
  const filledLength = circumference * fillPercent;
  const emptyLength = circumference - filledLength;

  return (
    <div className="bg-surface rounded-xl border border-border p-6 flex flex-col items-center">
      <p className="text-sm text-muted mb-4">Reserve Health</p>
      <div className="relative">
        <svg width="160" height="90" viewBox="0 0 160 90">
          {/* Background arc */}
          <path
            d={`M ${cx - radius} ${cy} A ${radius} ${radius} 0 0 1 ${cx + radius} ${cy}`}
            fill="none"
            stroke="#374151"
            strokeWidth={strokeWidth}
            strokeLinecap="round"
          />
          {/* Filled arc */}
          <path
            d={`M ${cx - radius} ${cy} A ${radius} ${radius} 0 0 1 ${cx + radius} ${cy}`}
            fill="none"
            stroke={color}
            strokeWidth={strokeWidth}
            strokeLinecap="round"
            strokeDasharray={`${filledLength} ${emptyLength}`}
          />
        </svg>
        <div className="absolute inset-0 flex items-end justify-center pb-1">
          <span className="font-mono tabular-nums text-xl text-white" style={{ color }}>
            {formatBps(reserveLevel)}
          </span>
        </div>
      </div>
    </div>
  );
}
