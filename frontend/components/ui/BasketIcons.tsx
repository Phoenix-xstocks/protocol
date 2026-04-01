import { TokenIcon } from './TokenIcon';
import { XSTOCKS } from '@/lib/constants';

interface BasketIconsProps {
  addresses: readonly string[];
  size?: 'sm' | 'md' | 'lg';
}

const addressToSymbol: Record<string, string> = Object.fromEntries(
  Object.values(XSTOCKS).map((s) => [s.address.toLowerCase(), s.symbol])
);

export function BasketIcons({ addresses, size = 'sm' }: BasketIconsProps) {
  return (
    <div className="flex -space-x-1.5">
      {addresses.map((addr) => (
        <TokenIcon
          key={addr}
          symbol={addressToSymbol[addr.toLowerCase()] || '??'}
          size={size}
        />
      ))}
    </div>
  );
}
