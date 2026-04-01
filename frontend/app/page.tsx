import { Hero } from '@/components/landing/Hero';
import { HowItWorks } from '@/components/landing/HowItWorks';
import { LiveStats } from '@/components/landing/LiveStats';
import { APYComparison } from '@/components/landing/APYComparison';

export default function LandingPage() {
  return (
    <div>
      <Hero />
      <LiveStats />
      <APYComparison />
      <HowItWorks />
    </div>
  );
}
