'use client';

import { useState, useEffect } from 'react';
import { formatDuration } from '@/lib/format';

interface CountdownTimerProps {
  targetTimestamp: number;
  label?: string;
  onComplete?: () => void;
  className?: string;
}

export function CountdownTimer({ targetTimestamp, label, onComplete, className = '' }: CountdownTimerProps) {
  const [remaining, setRemaining] = useState(0);

  useEffect(() => {
    const update = () => {
      const now = Math.floor(Date.now() / 1000);
      const diff = targetTimestamp - now;
      if (diff <= 0) {
        setRemaining(0);
        onComplete?.();
        return;
      }
      setRemaining(diff);
    };

    update();
    const interval = setInterval(update, 1000);
    return () => clearInterval(interval);
  }, [targetTimestamp, onComplete]);

  return (
    <div className={`font-mono tabular-nums ${className}`}>
      {label && <span className="text-muted text-sm mr-2">{label}</span>}
      <span className={remaining <= 3600 ? 'text-loss' : 'text-white'}>
        {remaining > 0 ? formatDuration(remaining) : 'Expired'}
      </span>
    </div>
  );
}
