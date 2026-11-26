"use client";

import { ShoppingBag } from "lucide-react";
import { useCart } from "./CartProvider";

/// Muestra cuántas unidades de un plato hay en el carrito sobre su imagen.
export function CartQuantityBadge({ menuItemId }: { menuItemId: string }) {
  const { lines, ready } = useCart();
  const quantity = ready
    ? (lines.find((line) => line.menuItemId === menuItemId)?.quantity ?? 0)
    : 0;

  if (quantity <= 0) return null;

  return (
    <span
      className="absolute bottom-3 right-3 z-10 inline-flex min-w-8 items-center justify-center gap-1 rounded-full bg-brand px-2 py-1 text-xs font-bold text-white shadow-lg ring-2 ring-surface-raised/80"
      aria-label={`${quantity} en el carrito`}
    >
      <ShoppingBag size={12} aria-hidden />
      {quantity}
    </span>
  );
}
