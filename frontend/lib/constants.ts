export const XSTOCKS = {
  NVDAx: {
    address: '0x3EfB67e01d5Ab3dd37dBb34D8a8c09D0682Bfc4E' as const,
    symbol: 'NVDAx',
    name: 'NVIDIA',
    color: '#76b900',
  },
  TSLAx: {
    address: '0x2a968432b2BC26dA460A0B7262414552288C894E' as const,
    symbol: 'TSLAx',
    name: 'Tesla',
    color: '#cc0000',
  },
  METAx: {
    address: '0x7EA9266A024e168341827a9c4621EC5b16cda65a' as const,
    symbol: 'METAx',
    name: 'Meta',
    color: '#0668E1',
  },
} as const;

export const FLAGSHIP_BASKET = [
  XSTOCKS.NVDAx.address,
  XSTOCKS.TSLAx.address,
  XSTOCKS.METAx.address,
] as const;

export const PROTOCOL_CONSTANTS = {
  MIN_NOTE_SIZE: 100_000_000n, // 100 USDC (6 decimals)
  MAX_NOTE_SIZE: 100_000_000_000n, // 100k USDC
  MAX_TVL: 5_000_000_000_000n, // 5M USDC
  EMBEDDED_FEE_BPS: 50n, // 0.5%
  ORIGINATION_FEE_BPS: 10n, // 0.1%
  TOTAL_FEE_BPS: 60n, // 0.6%
  MAX_OBSERVATIONS: 6,
  OBS_INTERVAL_DAYS: 30,
  MATURITY_DAYS: 180,
  COUPON_BARRIER_BPS: 7_000, // 70%
  AUTOCALL_TRIGGER_BPS: 10_000, // 100%
  STEP_DOWN_BPS: 200, // 2%
  KI_BARRIER_BPS: 5_000, // 50%
  KI_SETTLE_DEADLINE_DAYS: 7,
  CLAIM_DEADLINE_HOURS: 24,
  EPOCH_DURATION_HOURS: 48,
  USDC_DECIMALS: 6,
} as const;

export const TARGET_APY_BPS = 1_200; // 12%
