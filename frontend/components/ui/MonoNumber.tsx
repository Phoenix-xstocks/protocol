interface MonoNumberProps {
  value: string;
  prefix?: string;
  suffix?: string;
  className?: string;
  size?: 'sm' | 'md' | 'lg' | 'xl';
}

const sizeClasses = {
  sm: 'text-sm',
  md: 'text-base',
  lg: 'text-xl',
  xl: 'text-3xl',
};

export function MonoNumber({ value, prefix, suffix, className = '', size = 'md' }: MonoNumberProps) {
  return (
    <span className={`font-mono tabular-nums ${sizeClasses[size]} ${className}`}>
      {prefix && <span className="text-muted">{prefix}</span>}
      {value}
      {suffix && <span className="text-muted ml-1">{suffix}</span>}
    </span>
  );
}
