const USDC_DECIMALS = 6;

export function formatUSDC(amount: bigint, decimals = 2): string {
  const value = Number(amount) / 10 ** USDC_DECIMALS;
  return value.toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

export function formatUSDCCompact(amount: bigint): string {
  const value = Number(amount) / 10 ** USDC_DECIMALS;
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}K`;
  return value.toFixed(2);
}

export function formatBps(bps: number | bigint): string {
  const value = Number(bps) / 100;
  return `${value.toFixed(2)}%`;
}

export function formatPercent(value: number, decimals = 2): string {
  return `${value.toFixed(decimals)}%`;
}

export function formatDuration(seconds: number): string {
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

export function parseUSDC(amount: string): bigint {
  const value = parseFloat(amount);
  if (isNaN(value) || value < 0) return 0n;
  return BigInt(Math.floor(value * 10 ** USDC_DECIMALS));
}

export function shortenAddress(address: string, chars = 4): string {
  return `${address.slice(0, chars + 2)}...${address.slice(-chars)}`;
}
