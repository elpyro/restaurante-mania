"use client";

import { useState } from "react";
import { useCart } from "./CartProvider";
import type { MenuItem } from "@/lib/types";

interface Props {
  item: Pick<MenuItem, "id" | "name" | "price" | "emoji" | "status">;
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
  const { add } = useCart();
  const [added, setAdded] = useState(false);
  const disabled = item.status === "unavailable";

  return (
    <button
      type="button"
      disabled={disabled}
      onClick={() => {
        add(item, quantity);
        setAdded(true);
        window.setTimeout(() => setAdded(false), 1400);
      }}
      className={
        className ??
        `inline-flex items-center justify-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold transition ${
          disabled
            ? "cursor-not-allowed bg-stone-200 text-stone-500"
            : "bg-brand-600 text-white hover:bg-brand-700 active:scale-[0.98]"
        }`
      }
    >
      {disabled ? "No disponible" : added ? "¡Agregado! ✓" : `+ ${label}`}
    </button>
  );
}
