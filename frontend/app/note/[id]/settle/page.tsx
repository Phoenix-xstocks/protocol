import { PageContainer } from '@/components/layout/PageContainer';

export default async function SettlePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <PageContainer title={`Settle Note #${id}`} subtitle="Choose your settlement option">
      <div className="bg-surface rounded-xl border border-border p-8 text-center text-muted">
        KI Settlement coming in Phase 5
      </div>
    </PageContainer>
  );
}
