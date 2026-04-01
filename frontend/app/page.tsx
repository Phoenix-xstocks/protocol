import { PageContainer } from '@/components/layout/PageContainer';

export default function LandingPage() {
  return (
    <PageContainer>
      <div className="text-center py-20">
        <h1 className="text-5xl font-bold text-white mb-4">
          Structured Yield on
          <span className="text-accent"> Tokenized Equities</span>
        </h1>
        <p className="text-lg text-muted max-w-2xl mx-auto mb-8">
          Permissionless autocall notes with real-time coupon streaming.
          Up to 12% APY backed by on-chain option pricing and delta-neutral hedging.
        </p>
        <div className="flex gap-4 justify-center">
          <a
            href="/deposit"
            className="px-6 py-3 bg-accent hover:bg-accent-dim text-white rounded-lg font-medium transition-colors"
          >
            Start Earning
          </a>
          <a
            href="/dashboard"
            className="px-6 py-3 bg-surface-2 hover:bg-border text-white rounded-lg font-medium transition-colors border border-border"
          >
            View Dashboard
          </a>
        </div>
      </div>
    </PageContainer>
  );
}
