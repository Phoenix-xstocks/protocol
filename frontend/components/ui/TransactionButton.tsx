'use client';

interface TransactionButtonProps {
  label: string;
  onClick: () => void;
  isLoading?: boolean;
  isSuccess?: boolean;
  isError?: boolean;
  disabled?: boolean;
  variant?: 'primary' | 'secondary';
  className?: string;
}

export function TransactionButton({
  label,
  onClick,
  isLoading = false,
  isSuccess = false,
  isError = false,
  disabled = false,
  variant = 'primary',
  className = '',
}: TransactionButtonProps) {
  const baseClasses = 'px-6 py-3 rounded-lg font-medium transition-all text-sm disabled:opacity-50 disabled:cursor-not-allowed';
  const variantClasses = variant === 'primary'
    ? 'bg-accent hover:bg-accent-dim text-white'
    : 'bg-surface-2 hover:bg-border text-white border border-border';

  const stateLabel = isLoading ? 'Confirming...' : isSuccess ? 'Success' : isError ? 'Failed' : label;

  return (
    <button
      onClick={onClick}
      disabled={disabled || isLoading}
      className={`${baseClasses} ${variantClasses} ${className}`}
    >
      <span className="flex items-center justify-center gap-2">
        {isLoading && (
          <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
        )}
        {stateLabel}
      </span>
    </button>
  );
}
