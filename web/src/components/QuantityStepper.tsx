"use client";

import { Minus, Plus } from "lucide-react";

interface Props {
  value: number;
  onChange: (value: number) => void;
  min?: number;
  max?: number;
  label?: string;
}

export function QuantityStepper({
  value,
  onChange,
  min = 1,
  max = 99,
  label = "Cantidad",
}: Props) {
  return (
    <div
      className="inline-flex items-center rounded-full border border-line bg-surface-raised"
      role="group"
      aria-label={label}
    >
      <button
        type="button"
        aria-label="Disminuir cantidad"
        onClick={() => onChange(Math.max(min, value - 1))}
        disabled={value <= min}
        className="grid h-8 w-8 place-items-center rounded-full text-ink-soft transition hover:bg-brand-50 disabled:cursor-not-allowed disabled:text-ink-400"
      >
        <Minus size={15} aria-hidden />
      </button>
      <span className="min-w-7 text-center text-sm font-bold tabular-nums text-ink">
        {value}
      </span>
      <button
        type="button"
        aria-label="Aumentar cantidad"
        onClick={() => onChange(Math.min(max, value + 1))}
        disabled={value >= max}
        className="grid h-8 w-8 place-items-center rounded-full text-ink-soft transition hover:bg-brand-50 disabled:cursor-not-allowed disabled:text-ink-400"
      >
        <Plus size={15} aria-hidden />
      </button>
    </div>
  );
}
