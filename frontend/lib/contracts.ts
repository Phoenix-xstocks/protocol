import { XYieldVaultABI } from './abis/XYieldVault';
import { AutocallEngineABI } from './abis/AutocallEngine';
import { ProtocolStatsABI } from './abis/ProtocolStats';
import { SablierStreamABI } from './abis/SablierStream';
import { EpochManagerABI } from './abis/EpochManager';
import { ERC20ABI } from './abis/ERC20';
import { NoteTokenABI } from './abis/NoteToken';

export const CONTRACTS = {
  XYieldVault: {
    address: '0x72470eDB59e433E33FB7a70fE97eF0291bf25D6E' as const,
    abi: XYieldVaultABI,
  },
  AutocallEngine: {
    address: '0x65cBd62cF76b4B2fE19d0e199A06550f74d5bB4e' as const,
    abi: AutocallEngineABI,
  },
  ProtocolStats: {
    address: '0x0000000000000000000000000000000000000000' as const, // TODO: update after deployment
    abi: ProtocolStatsABI,
  },
  SablierStream: {
    address: '0x0000000000000000000000000000000000000000' as const, // TODO: update after deployment
    abi: SablierStreamABI,
  },
  EpochManager: {
    address: '0x0000000000000000000000000000000000000000' as const, // TODO: update after deployment
    abi: EpochManagerABI,
  },
  USDC: {
    address: '0x6b57475467cd854d36Be7FB614caDa5207838943' as const,
    abi: ERC20ABI,
  },
} as const;
