"use client";

import Image from "next/image";
import Link from "next/link";
import { ArrowLeft, ShieldCheck, ShoppingBag, Trash2, Wallet } from "lucide-react";
import { useCart } from "./CartProvider";
import { QuantityStepper } from "./QuantityStepper";
import { formatCOP } from "@/lib/format";

export function CartView() {
  const { lines, totals, ready, setQuantity, remove, clear } = useCart();

  if (!ready) {
    return (
      <div className="space-y-3" aria-busy="true">
        <div className="skeleton h-24" />
        <div className="skeleton h-24" />
      </div>
    );
  }

  if (lines.length === 0) {
    return (
      <div className="surface-card border-dashed p-12 text-center">
        <span className="mx-auto grid h-16 w-16 place-items-center rounded-3xl bg-brand-50 text-brand">
          <ShoppingBag size={28} aria-hidden />
        </span>
        <h2 className="mt-5 font-display text-2xl font-bold text-ink">
          Tu carrito está vacío
        </h2>
        <p className="mt-2 text-sm text-ink-muted">
          Agrega tus platos favoritos y vuelve aquí para confirmar el pedido.
        </p>
        <Link href="/menu" className="btn-primary mt-6">
          Explorar el menú <ArrowLeft size={15} className="rotate-180" aria-hidden />
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
            className="surface-card flex items-center gap-4 p-4"
          >
            {line.imageUrl ? (
              <Image
                src={line.imageUrl}
                alt={line.name}
                width={72}
                height={72}
                className="h-16 w-16 shrink-0 rounded-2xl object-cover"
              />
            ) : (
              <span className="grid h-16 w-16 shrink-0 place-items-center rounded-2xl bg-gradient-to-br from-brand-100 to-accent-soft text-3xl">
                {line.emoji}
              </span>
            )}
            <div className="min-w-0 flex-1">
              <h3 className="truncate font-semibold text-ink">{line.name}</h3>
              <p className="text-sm text-ink-muted">{formatCOP(line.price)} c/u</p>
              <button
                type="button"
                onClick={() => remove(line.menuItemId)}
                className="mt-1 inline-flex items-center gap-1 text-xs font-medium text-brand-strong hover:underline"
              >
                <Trash2 size={12} aria-hidden /> Quitar
              </button>
            </div>
            <div className="flex flex-col items-end gap-2">
              <QuantityStepper
                value={line.quantity}
                max={typeof line.maxServings === "number" ? Math.max(1, line.maxServings) : 99}
                onChange={(quantity) => setQuantity(line.menuItemId, quantity)}
              />
              {typeof line.maxServings === "number" && line.quantity >= line.maxServings ? (
                <p className="text-[11px] font-medium text-brand-strong">Máx. por insumos</p>
              ) : null}
              <p className="text-sm font-bold text-ink">
                {formatCOP(line.price * line.quantity)}
              </p>
            </div>
          </article>
        ))}
        <div className="flex items-center justify-between pt-2">
          <Link href="/menu" className="inline-flex items-center gap-1 text-sm font-medium text-brand-strong hover:underline">
            <ArrowLeft size={14} aria-hidden /> Seguir pidiendo
          </Link>
          <button
            type="button"
            onClick={clear}
            className="text-xs font-medium text-ink-muted hover:text-brand-strong hover:underline"
          >
            Vaciar carrito
          </button>
        </div>
      </div>

      <aside className="surface-card h-fit p-5 lg:sticky lg:top-24">
        <h2 className="inline-flex items-center gap-2 font-display text-xl font-bold text-ink">
          <Wallet size={18} className="text-brand" aria-hidden /> Resumen
        </h2>
        <dl className="mt-4 space-y-2 text-sm">
          <div className="flex justify-between">
            <dt className="text-ink-muted">
              Subtotal ({totals.count} producto{totals.count === 1 ? "" : "s"})
            </dt>
            <dd className="font-medium text-ink">{formatCOP(totals.subtotal)}</dd>
          </div>
          <div className="flex justify-between">
            <dt className="text-ink-muted">Impuestos</dt>
            <dd className="font-medium text-ink">
              {totals.tax === 0 ? "Incluidos" : formatCOP(totals.tax)}
            </dd>
          </div>
          <div className="flex justify-between border-t border-line pt-3 text-base">
            <dt className="font-bold text-ink">Total</dt>
            <dd className="font-bold text-brand-strong">{formatCOP(totals.total)}</dd>
          </div>
        </dl>
        <Link href="/checkout" className="btn-primary mt-5 w-full">
          Continuar con el pedido <ArrowLeft size={15} className="rotate-180" aria-hidden />
        </Link>
        <p className="mt-3 flex items-center justify-center gap-1.5 text-center text-xs text-ink-muted">
          <ShieldCheck size={13} className="text-accent" aria-hidden />
          Pago contra entrega o en el restaurante.
        </p>
      </aside>
    </div>
  );
}
