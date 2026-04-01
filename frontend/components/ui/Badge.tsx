interface BadgeProps {
  label: string;
  color?: string;
  bgColor?: string;
  className?: string;
}

export function Badge({ label, color = 'text-gray-400', bgColor = 'bg-gray-400/10', className = '' }: BadgeProps) {
  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${color} ${bgColor} ${className}`}>
      {label}
    </span>
  );
}
