"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ArrowRight, ShoppingBag } from "lucide-react";
import { formatCOP } from "@/lib/format";
import { useCart } from "./CartProvider";

/// Barra flotante inferior con el monto actual del carrito. Se oculta en las
/// páginas donde el carrito ya está a la vista para no duplicar controles.
export function FloatingCartBar() {
  const pathname = usePathname();
  const { count, totals, ready } = useCart();
  const onCartPage =
    pathname === "/cart" ||
    pathname === "/checkout" ||
    pathname.startsWith("/order/");

  if (!ready || count === 0 || onCartPage) return null;

  return (
    <Link
      href="/cart"
      aria-label={`Ver carrito: ${count} productos, total ${formatCOP(totals.total)}`}
      className="fixed bottom-4 left-1/2 z-50 flex w-[calc(100%-2rem)] max-w-sm -translate-x-1/2 items-center justify-between gap-3 rounded-full bg-brand px-5 py-3 text-white shadow-glow transition duration-300 hover:-translate-y-0.5 hover:bg-brand-strong md:bottom-6"
    >
      <span className="inline-flex items-center gap-2 text-sm font-semibold">
        <ShoppingBag size={18} aria-hidden />
        Carrito
        <span className="grid h-6 min-w-6 place-items-center rounded-full bg-white/20 px-1 text-[11px] font-bold">
          {count}
        </span>
      </span>
      <span className="inline-flex items-center gap-2 font-display text-base font-bold">
        {formatCOP(totals.total)}
        <ArrowRight size={16} aria-hidden />
      </span>
    </Link>
  );
}
