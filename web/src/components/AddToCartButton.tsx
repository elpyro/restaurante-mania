"use client";

import { useState } from "react";
import { CircleCheck, Plus } from "lucide-react";
import { useCart } from "./CartProvider";
import type { MenuItem } from "@/lib/types";

interface Props {
  item: Pick<
    MenuItem,
    "id" | "name" | "price" | "emoji" | "imageUrl" | "status" | "maxServings"
  >;
  quantity?: number;
  className?: string;
  label?: string;
}

export function AddToCartButton({
  item,
  quantity = 1,
  className,
  label = "Agregar",
}: Props) {
  const { add, lines } = useCart();
  const [added, setAdded] = useState(false);
  const [limitedMsg, setLimitedMsg] = useState(false);
  const line = lines.find((l) => l.menuItemId === item.id);
  const max = item.maxServings ?? line?.maxServings ?? null;
  const atMax = typeof max === "number" && (line?.quantity ?? 0) >= max;
  const disabled = item.status === "unavailable" || atMax;

  return (
    <div className="inline-flex flex-col items-end gap-1">
      <button
        type="button"
        disabled={disabled}
        onClick={() => {
          const result = add(item, quantity);
          if (result.added) {
            setAdded(true);
            window.setTimeout(() => setAdded(false), 1400);
          } else if (result.limited || atMax) {
            setLimitedMsg(true);
            window.setTimeout(() => setLimitedMsg(false), 2200);
          }
        }}
        className={
          className ??
          `inline-flex items-center justify-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold transition ${
            disabled
              ? "cursor-not-allowed bg-surface-muted text-ink-400"
              : added
                ? "bg-accent text-white"
                : "bg-brand text-white hover:bg-brand-strong active:scale-[0.98]"
          }`
        }
      >
        {item.status === "unavailable"
          ? "No disponible"
          : atMax
            ? "Límite por insumos"
            : added
              ? (
                <>
                  <CircleCheck size={15} aria-hidden /> ¡Agregado!
                </>
              )
              : (
                <>
                  <Plus size={15} aria-hidden /> {label}
                </>
              )}
      </button>
      {limitedMsg && !atMax ? (
        <span className="text-[11px] font-medium text-brand-strong">
          Sin ingredientes para más unidades
        </span>
      ) : null}
    </div>
  );
}
