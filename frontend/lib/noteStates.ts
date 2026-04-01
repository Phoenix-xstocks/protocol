export enum NoteState {
  Created = 0,
  Priced = 1,
  Active = 2,
  ObservationPending = 3,
  Autocalled = 4,
  MaturityCheck = 5,
  KISettle = 6,
  NoKISettle = 7,
  Settled = 8,
  Rolled = 9,
  Cancelled = 10,
  EmergencyPaused = 11,
}

interface StateConfig {
  label: string;
  color: string;
  bgColor: string;
  description: string;
}

export const NOTE_STATE_CONFIG: Record<NoteState, StateConfig> = {
  [NoteState.Created]: {
    label: 'Created',
    color: 'text-gray-400',
    bgColor: 'bg-gray-400/10',
    description: 'Note created, awaiting pricing',
  },
  [NoteState.Priced]: {
    label: 'Priced',
    color: 'text-cyan-400',
    bgColor: 'bg-cyan-400/10',
    description: 'Pricing received, awaiting activation',
  },
  [NoteState.Active]: {
    label: 'Active',
    color: 'text-green-400',
    bgColor: 'bg-green-400/10',
    description: 'Note is active, accruing coupons',
  },
  [NoteState.ObservationPending]: {
    label: 'Observation',
    color: 'text-yellow-400',
    bgColor: 'bg-yellow-400/10',
    description: 'Monthly observation due',
  },
  [NoteState.Autocalled]: {
    label: 'Autocalled',
    color: 'text-green-500',
    bgColor: 'bg-green-500/10',
    description: 'Autocall triggered, settling',
  },
  [NoteState.MaturityCheck]: {
    label: 'Maturity',
    color: 'text-blue-400',
    bgColor: 'bg-blue-400/10',
    description: 'At maturity, checking KI barrier',
  },
  [NoteState.KISettle]: {
    label: 'KI Settle',
    color: 'text-red-400',
    bgColor: 'bg-red-400/10',
    description: 'KI breached, choose settlement',
  },
  [NoteState.NoKISettle]: {
    label: 'No KI',
    color: 'text-green-400',
    bgColor: 'bg-green-400/10',
    description: 'No KI breach, settling at par',
  },
  [NoteState.Settled]: {
    label: 'Settled',
    color: 'text-gray-500',
    bgColor: 'bg-gray-500/10',
    description: 'Note fully settled',
  },
  [NoteState.Rolled]: {
    label: 'Rolled',
    color: 'text-purple-400',
    bgColor: 'bg-purple-400/10',
    description: 'Rolled into new note',
  },
  [NoteState.Cancelled]: {
    label: 'Cancelled',
    color: 'text-red-500',
    bgColor: 'bg-red-500/10',
    description: 'Note cancelled',
  },
  [NoteState.EmergencyPaused]: {
    label: 'Paused',
    color: 'text-orange-400',
    bgColor: 'bg-orange-400/10',
    description: 'Emergency pause active',
  },
};
