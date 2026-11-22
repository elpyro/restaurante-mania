"use client";

import Link from "next/link";
import { useCart } from "./CartProvider";
import { QuantityStepper } from "./QuantityStepper";
import { formatCOP } from "@/lib/format";

export function CartView() {
  const { lines, totals, ready, setQuantity, remove, clear } = useCart();

  if (!ready) {
    return (
      <div className="space-y-3" aria-busy="true">
        <div className="h-24 animate-pulse rounded-2xl bg-stone-200" />
        <div className="h-24 animate-pulse rounded-2xl bg-stone-200" />
      </div>
    );
  }

  if (lines.length === 0) {
    return (
      <div className="rounded-3xl border border-dashed border-stone-300 bg-white p-12 text-center">
        <p className="text-5xl">🛒</p>
        <h2 className="mt-4 font-display text-2xl font-bold text-ink-900">
          Tu carrito está vacío
        </h2>
        <p className="mt-2 text-sm text-ink-500">
          Agrega tus platos favoritos y vuelve aquí para confirmar el pedido.
        </p>
        <Link
          href="/menu"
          className="mt-6 inline-flex rounded-full bg-brand-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-brand-700"
        >
          Explorar el menú
        </Link>
      </div>
    );
  }

  return (
    <div className="grid gap-8 lg:grid-cols-[1.6fr_1fr]">
      <div className="space-y-3">
        {lines.map((line) => (
          <article
            key={line.menuItemId}
            className="flex items-center gap-4 rounded-2xl border border-stone-200 bg-white p-4"
          >
            <span className="grid h-16 w-16 shrink-0 place-items-center rounded-xl bg-gradient-to-br from-brand-100 to-amber-50 text-3xl">
              {line.emoji}
            </span>
            <div className="min-w-0 flex-1">
              <h3 className="truncate font-semibold text-ink-900">{line.name}</h3>
              <p className="text-sm text-ink-500">{formatCOP(line.price)} c/u</p>
              <button
                type="button"
                onClick={() => remove(line.menuItemId)}
                className="mt-1 text-xs font-medium text-rose-600 hover:underline"
              >
                Quitar
              </button>
            </div>
            <div className="flex flex-col items-end gap-2">
              <QuantityStepper
                value={line.quantity}
                onChange={(quantity) => setQuantity(line.menuItemId, quantity)}
              />
              <p className="text-sm font-bold text-ink-900">
                {formatCOP(line.price * line.quantity)}
              </p>
            </div>
          </article>
        ))}
        <div className="flex items-center justify-between pt-2">
          <Link href="/menu" className="text-sm font-medium text-brand-700 hover:underline">
            ← Seguir pidiendo
          </Link>
          <button
            type="button"
            onClick={clear}
            className="text-xs font-medium text-ink-500 hover:text-rose-600 hover:underline"
          >
            Vaciar carrito
          </button>
        </div>
      </div>

      <aside className="h-fit rounded-2xl border border-stone-200 bg-white p-5 lg:sticky lg:top-24">
        <h2 className="font-display text-xl font-bold text-ink-900">Resumen</h2>
        <dl className="mt-4 space-y-2 text-sm">
          <div className="flex justify-between">
            <dt className="text-ink-500">
              Subtotal ({totals.count} producto{totals.count === 1 ? "" : "s"})
            </dt>
            <dd className="font-medium text-ink-900">{formatCOP(totals.subtotal)}</dd>
          </div>
          <div className="flex justify-between">
            <dt className="text-ink-500">Impuestos</dt>
            <dd className="font-medium text-ink-900">
              {totals.tax === 0 ? "Incluidos" : formatCOP(totals.tax)}
            </dd>
          </div>
          <div className="flex justify-between border-t border-stone-200 pt-3 text-base">
            <dt className="font-bold text-ink-900">Total</dt>
            <dd className="font-bold text-brand-700">{formatCOP(totals.total)}</dd>
          </div>
        </dl>
        <Link
          href="/checkout"
          className="mt-5 block rounded-full bg-brand-600 px-5 py-3 text-center text-sm font-bold text-white transition hover:bg-brand-700"
        >
          Continuar con el pedido
        </Link>
        <p className="mt-3 text-center text-xs text-ink-500">
          Pago contra entrega o en el restaurante.
        </p>
      </aside>
    </div>
  );
}
