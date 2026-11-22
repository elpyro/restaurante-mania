"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useCart } from "./CartProvider";
import { formatCOP } from "@/lib/format";
import type { Order, OrderType, PaymentMethod } from "@/lib/types";

const typeOptions: Array<{ value: OrderType; label: string; icon: string }> = [
  { value: "pickup", label: "Para recoger", icon: "🛍️" },
  { value: "delivery", label: "Domicilio", icon: "🛵" },
  { value: "table", label: "En mesa", icon: "🍽️" },
];

const paymentOptions: Array<{ value: PaymentMethod; label: string }> = [
  { value: "cash", label: "Efectivo" },
  { value: "card", label: "Tarjeta" },
  { value: "nequi", label: "Nequi" },
  { value: "daviplata", label: "Daviplata" },
];

export function CheckoutForm() {
  const router = useRouter();
  const { lines, totals, ready, clear } = useCart();
  const [customerName, setCustomerName] = useState("");
  const [customerPhone, setCustomerPhone] = useState("");
  const [type, setType] = useState<OrderType>("pickup");
  const [tableNumber, setTableNumber] = useState("1");
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>("cash");
  const [notes, setNotes] = useState("");
  const [errors, setErrors] = useState<string[]>([]);
  const [submitting, setSubmitting] = useState(false);

  if (!ready) {
    return <div className="h-64 animate-pulse rounded-2xl bg-stone-200" />;
  }

  if (lines.length === 0) {
    return (
      <div className="rounded-3xl border border-dashed border-stone-300 bg-white p-12 text-center">
        <p className="text-5xl">🧾</p>
        <h2 className="mt-4 font-display text-2xl font-bold text-ink-900">
          No hay productos para confirmar
        </h2>
        <p className="mt-2 text-sm text-ink-500">
          Agrega algo del menú antes de continuar con el pedido.
        </p>
        <Link
          href="/menu"
          className="mt-6 inline-flex rounded-full bg-brand-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-brand-700"
        >
          Ir al menú
        </Link>
      </div>
    );
  }

  function validate(): string[] {
    const found: string[] = [];
    if (customerName.trim().length < 2) found.push("Escribe tu nombre completo.");
    if (customerPhone.replace(/\D/g, "").length < 7) {
      found.push("Escribe un teléfono válido (mínimo 7 dígitos).");
    }
    if (type === "table") {
      const table = Number(tableNumber);
      if (!Number.isInteger(table) || table < 1 || table > 100) {
        found.push("El número de mesa debe estar entre 1 y 100.");
      }
    }
    return found;
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const clientErrors = validate();
    if (clientErrors.length > 0) {
      setErrors(clientErrors);
      return;
    }
    setErrors([]);
    setSubmitting(true);
    try {
      const response = await fetch("/api/orders", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          customerName,
          customerPhone,
          type,
          tableNumber: type === "table" ? Number(tableNumber) : null,
          paymentMethod,
          notes,
          items: lines.map((line) => ({
            menuItemId: line.menuItemId,
            quantity: line.quantity,
          })),
        }),
      });
      const payload = (await response.json()) as {
        order?: Order;
        errors?: string[];
      };
      if (!response.ok || !payload.order) {
        setErrors(payload.errors ?? ["No pudimos crear el pedido. Intenta de nuevo."]);
        return;
      }
      const order = payload.order;
      try {
        window.sessionStorage.setItem(`rm_order_${order.id}`, JSON.stringify(order));
        const raw = window.localStorage.getItem("rm_orders_v1");
        const stored = raw ? (JSON.parse(raw) as Order[]) : [];
        window.localStorage.setItem(
          "rm_orders_v1",
          JSON.stringify([order, ...stored].slice(0, 50)),
        );
        window.localStorage.setItem("rm_last_order_id", order.id);
      } catch {
        /* el pedido ya fue creado en el servidor */
      }
      clear();
      router.push(`/order/${order.id}`);
    } catch {
      setErrors(["Error de red. Revisa tu conexión e intenta de nuevo."]);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="grid gap-8 lg:grid-cols-[1.5fr_1fr]">
      <div className="space-y-6">
        <section className="rounded-2xl border border-stone-200 bg-white p-5">
          <h2 className="font-display text-xl font-bold text-ink-900">Tus datos</h2>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            <label className="block text-sm">
              <span className="mb-1.5 block font-medium text-ink-700">
                Nombre completo *
              </span>
              <input
                required
                value={customerName}
                onChange={(event) => setCustomerName(event.target.value)}
                className="w-full rounded-xl border border-stone-300 px-3 py-2.5 outline-none focus:border-brand-500 focus:ring-2 focus:ring-brand-200"
                placeholder="Ana Pérez"
                autoComplete="name"
              />
            </label>
            <label className="block text-sm">
              <span className="mb-1.5 block font-medium text-ink-700">
                Teléfono / WhatsApp *
              </span>
              <input
                required
                value={customerPhone}
                onChange={(event) => setCustomerPhone(event.target.value)}
                className="w-full rounded-xl border border-stone-300 px-3 py-2.5 outline-none focus:border-brand-500 focus:ring-2 focus:ring-brand-200"
                placeholder="300 123 4567"
                inputMode="tel"
                autoComplete="tel"
              />
            </label>
          </div>
        </section>

        <section className="rounded-2xl border border-stone-200 bg-white p-5">
          <h2 className="font-display text-xl font-bold text-ink-900">
            ¿Cómo quieres recibirlo?
          </h2>
          <div className="mt-4 grid gap-3 sm:grid-cols-3">
            {typeOptions.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => setType(option.value)}
                className={`rounded-xl border p-3 text-left transition ${
                  type === option.value
                    ? "border-brand-500 bg-brand-50 ring-2 ring-brand-200"
                    : "border-stone-200 hover:border-brand-300"
                }`}
              >
                <span className="text-2xl">{option.icon}</span>
                <span className="mt-1 block text-sm font-semibold text-ink-900">
                  {option.label}
                </span>
              </button>
            ))}
          </div>
          {type === "table" ? (
            <label className="mt-4 block max-w-xs text-sm">
              <span className="mb-1.5 block font-medium text-ink-700">
                Número de mesa
              </span>
              <input
                type="number"
                min={1}
                max={100}
                value={tableNumber}
                onChange={(event) => setTableNumber(event.target.value)}
                className="w-full rounded-xl border border-stone-300 px-3 py-2.5 outline-none focus:border-brand-500 focus:ring-2 focus:ring-brand-200"
              />
            </label>
          ) : null}
        </section>

        <section className="rounded-2xl border border-stone-200 bg-white p-5">
          <h2 className="font-display text-xl font-bold text-ink-900">Pago</h2>
          <div className="mt-4 flex flex-wrap gap-2">
            {paymentOptions.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => setPaymentMethod(option.value)}
                className={`rounded-full border px-4 py-2 text-sm font-medium transition ${
                  paymentMethod === option.value
                    ? "border-ink-900 bg-ink-900 text-white"
                    : "border-stone-300 text-ink-700 hover:border-brand-400"
                }`}
              >
                {option.label}
              </button>
            ))}
          </div>
          <label className="mt-4 block text-sm">
            <span className="mb-1.5 block font-medium text-ink-700">
              Notas para la cocina (opcional)
            </span>
            <textarea
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              rows={3}
              maxLength={300}
              className="w-full rounded-xl border border-stone-300 px-3 py-2.5 outline-none focus:border-brand-500 focus:ring-2 focus:ring-brand-200"
              placeholder="Sin cebolla, salsa aparte..."
            />
          </label>
        </section>

        {errors.length > 0 ? (
          <div
            role="alert"
            className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700"
          >
            <p className="font-semibold">Revisa estos puntos:</p>
            <ul className="mt-1 list-inside list-disc">
              {errors.map((error) => (
                <li key={error}>{error}</li>
              ))}
            </ul>
          </div>
        ) : null}
      </div>

      <aside className="h-fit rounded-2xl border border-stone-200 bg-white p-5 lg:sticky lg:top-24">
        <h2 className="font-display text-xl font-bold text-ink-900">Tu pedido</h2>
        <ul className="mt-4 space-y-2 text-sm">
          {lines.map((line) => (
            <li key={line.menuItemId} className="flex justify-between gap-2">
              <span className="text-ink-700">
                {line.quantity} × {line.name}
              </span>
              <span className="whitespace-nowrap font-medium text-ink-900">
                {formatCOP(line.price * line.quantity)}
              </span>
            </li>
          ))}
        </ul>
        <div className="mt-4 flex justify-between border-t border-stone-200 pt-3 text-base">
          <span className="font-bold text-ink-900">Total</span>
          <span className="font-bold text-brand-700">{formatCOP(totals.total)}</span>
        </div>
        <button
          type="submit"
          disabled={submitting}
          className="mt-5 w-full rounded-full bg-brand-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-brand-700 disabled:cursor-wait disabled:opacity-60"
        >
          {submitting ? "Enviando pedido..." : "Confirmar pedido"}
        </button>
        <p className="mt-3 text-center text-xs text-ink-500">
          Al confirmar aceptas que te contactemos por WhatsApp.
        </p>
      </aside>
    </form>
  );
}
