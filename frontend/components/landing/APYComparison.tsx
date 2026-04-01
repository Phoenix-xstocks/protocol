'use client';

import { useEffect, useState } from 'react';

const MAX_APY = 14; // scale ceiling for bars

const comparisons = [
  { name: 'xYield Protocol', apy: 12, highlight: true },
  { name: 'Goldman Sachs Autocall', apy: 8, highlight: false },
  { name: 'US Treasury 10Y', apy: 4.5, highlight: false },
];

export function APYComparison() {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(id);
  }, []);

  return (
    <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
      <h2 className="text-3xl font-bold text-white text-center mb-14">
        Yield Comparison
      </h2>

      <div className="max-w-2xl mx-auto space-y-6">
        {comparisons.map((item) => {
          const widthPct = (item.apy / MAX_APY) * 100;

          return (
            <div key={item.name}>
              <div className="flex justify-between items-center mb-2">
                <span
                  className={`text-sm ${item.highlight ? 'text-white font-medium' : 'text-muted'}`}
                >
                  {item.name}
                </span>
                <span className="font-mono text-sm tabular-nums text-white">
                  {item.apy}%
                </span>
              </div>
              <div className="h-3 bg-surface-2 rounded-full overflow-hidden">
                <div
                  className={`h-full rounded-full transition-all duration-1000 ease-out ${
                    item.highlight
                      ? 'bg-accent shadow-[0_0_12px_rgba(6,182,212,0.4)]'
                      : 'bg-border'
                  }`}
                  style={{ width: mounted ? `${widthPct}%` : '0%' }}
                />
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
