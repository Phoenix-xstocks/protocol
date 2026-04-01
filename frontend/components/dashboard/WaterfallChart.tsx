'use client';

import { Skeleton } from '@/components/ui/Skeleton';
import { formatUSDC } from '@/lib/format';
import type { WaterfallResult } from '@/hooks/useWaterfallResult';

interface WaterfallChartProps {
  result: WaterfallResult | undefined;
  isLoading: boolean;
}

const SEGMENTS = [
  { key: 'p1Paid', label: 'P1 Base Coupons', color: '#06b6d4' },
  { key: 'p2Paid', label: 'P2 Principal', color: '#3b82f6' },
  { key: 'p3Paid', label: 'P3 Carry', color: '#22c55e' },
  { key: 'p4Paid', label: 'P4 Hedge', color: '#eab308' },
  { key: 'p5Paid', label: 'P5 Reserve', color: '#a855f7' },
  { key: 'p6Paid', label: 'P6 Treasury', color: '#6b7280' },
] as const;

export function WaterfallChart({ result, isLoading }: WaterfallChartProps) {
  if (isLoading || !result) {
    return (
      <div className="bg-surface rounded-xl border border-border p-6">
        <Skeleton className="h-5 w-48 mb-4" />
        <Skeleton className="h-10 w-full mb-4" />
        <div className="flex gap-4">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-4 w-20" />
          ))}
        </div>
      </div>
    );
  }

  const values = SEGMENTS.map((seg) => ({
    ...seg,
    value: result[seg.key],
  }));

  const total = values.reduce((sum, v) => sum + v.value, 0n);

  return (
    <div className="bg-surface rounded-xl border border-border p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm text-muted">Waterfall Distribution (Last Epoch)</h3>
        <span className="font-mono tabular-nums text-sm text-white">
          Total: ${formatUSDC(total)}
        </span>
      </div>

      {/* Stacked bar */}
      <div className="flex h-10 rounded-lg overflow-hidden mb-4">
        {values.map((seg) => {
          const width = total > 0n
            ? (Number(seg.value) / Number(total)) * 100
            : 0;
          if (width === 0) return null;
          return (
            <div
              key={seg.key}
              className="h-full transition-all duration-300"
              style={{
                width: `${width}%`,
                backgroundColor: seg.color,
                minWidth: width > 0 ? '2px' : 0,
              }}
              title={`${seg.label}: $${formatUSDC(seg.value)}`}
            />
          );
        })}
      </div>

      {/* Legend */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        {values.map((seg) => (
          <div key={seg.key} className="flex items-start gap-2">
            <div
              className="w-3 h-3 rounded-sm mt-0.5 shrink-0"
              style={{ backgroundColor: seg.color }}
            />
            <div className="min-w-0">
              <p className="text-xs text-muted truncate">{seg.label}</p>
              <p className="text-xs font-mono tabular-nums text-white">
                ${formatUSDC(seg.value)}
              </p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
