import Link from 'next/link';

const highlights = [
  { label: '180 Day Maturity' },
  { label: 'Monthly Observations' },
  { label: '50% KI Barrier' },
];

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      <div className="absolute inset-0 bg-gradient-to-b from-transparent via-transparent to-background pointer-events-none" />

      <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-24 pb-20 text-center">
        <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold text-white leading-tight tracking-tight">
          Structured Yield on{' '}
          <span className="text-accent">Tokenized Equities</span>
        </h1>

        <p className="mt-6 text-lg text-muted max-w-2xl mx-auto leading-relaxed">
          Permissionless autocall notes with real-time coupon streaming. Up to
          12% APY backed by on-chain option pricing and delta-neutral hedging.
        </p>

        <div className="mt-10 flex flex-col sm:flex-row gap-4 justify-center">
          <Link
            href="/deposit"
            className="px-8 py-3.5 bg-accent hover:bg-accent-dim text-white rounded-lg font-medium transition-colors text-base"
          >
            Start Earning
          </Link>
          <Link
            href="/dashboard"
            className="px-8 py-3.5 bg-surface-2 hover:bg-border text-white rounded-lg font-medium transition-colors border border-border text-base"
          >
            View Dashboard
          </Link>
        </div>

        <div className="mt-12 flex flex-wrap justify-center gap-6 sm:gap-10">
          {highlights.map((item) => (
            <div
              key={item.label}
              className="flex items-center gap-2 text-sm text-muted"
            >
              <span className="w-1.5 h-1.5 rounded-full bg-accent" />
              <span className="font-mono">{item.label}</span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
