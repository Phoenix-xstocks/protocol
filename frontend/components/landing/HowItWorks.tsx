const steps = [
  {
    number: 1,
    title: 'Deposit USDC',
    description:
      'Choose your basket of tokenized stocks and deposit USDC to create a note',
  },
  {
    number: 2,
    title: 'Earn Coupons',
    description:
      'Receive real-time streaming coupons via Sablier. ~12% APY from option premium + carry',
  },
  {
    number: 3,
    title: 'Monthly Observations',
    description:
      'Every 30 days, if worst-of stock is above autocall barrier, note is called early at par',
  },
  {
    number: 4,
    title: 'Settlement',
    description:
      'At maturity, receive full principal if no knock-in. If KI breached, choose physical or cash settlement',
  },
];

export function HowItWorks() {
  return (
    <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
      <h2 className="text-3xl font-bold text-white text-center mb-14">
        How It Works
      </h2>

      <div className="relative grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
        {/* Connector line -- visible only on large screens */}
        <div className="hidden lg:block absolute top-12 left-[12.5%] right-[12.5%] h-px bg-border" />

        {steps.map((step) => (
          <div
            key={step.number}
            className="relative bg-surface border border-border rounded-xl p-6"
          >
            <span className="block font-mono text-3xl font-bold text-accent mb-4">
              {step.number}
            </span>
            <h3 className="text-lg font-semibold text-white mb-2">
              {step.title}
            </h3>
            <p className="text-sm text-muted leading-relaxed">
              {step.description}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}
