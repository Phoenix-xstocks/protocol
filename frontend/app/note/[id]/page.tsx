import { PageContainer } from '@/components/layout/PageContainer';

export default async function NoteDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <PageContainer title={`Note #${id}`} subtitle="Note details and performance">
      <div className="bg-surface rounded-xl border border-border p-8 text-center text-muted">
        Note detail coming in Phase 4
      </div>
    </PageContainer>
  );
}
